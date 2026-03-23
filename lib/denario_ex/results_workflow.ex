defmodule DenarioEx.ResultsWorkflow do
  @moduledoc false

  alias DenarioEx.{
    AI,
    CMBAgentLoop,
    LLM,
    Progress,
    PythonExecutor,
    ReqLLMClient,
    Text,
    WorkflowPrompts
  }

  @engineer_schema %{
    "type" => "object",
    "additionalProperties" => false,
    "properties" => %{
      "summary" => %{"type" => "string"},
      "notes" => %{"type" => "string"},
      "code" => %{"type" => "string"}
    },
    "required" => ["summary", "notes", "code"]
  }

  @spec run(DenarioEx.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(session, opts \\ []) do
    client = Keyword.get(opts, :client, ReqLLMClient)
    executor = Keyword.get(opts, :executor, PythonExecutor)
    involved_agents = Keyword.get(opts, :involved_agents, ["engineer", "researcher"])
    max_n_steps = Keyword.get(opts, :max_n_steps, 6)
    max_n_attempts = Keyword.get(opts, :max_n_attempts, 10)
    restart_at_step = Keyword.get(opts, :restart_at_step, -1)
    hardware_constraints = Keyword.get(opts, :hardware_constraints, "")
    experiment_dir = Path.join(session.project_dir, "experiment")

    context = %{
      data_description: session.research.data_description,
      idea: session.research.idea,
      methodology: session.research.methodology,
      experiment_dir: experiment_dir
    }

    Progress.emit(opts, %{
      kind: :started,
      message: "Planning the results workflow.",
      progress: 8,
      stage: "results:start"
    })

    with {:ok, planner_llm} <- LLM.parse(Keyword.get(opts, :planner_model, "gpt-4o")),
         {:ok, reviewer_llm} <- LLM.parse(Keyword.get(opts, :plan_reviewer_model, "o3-mini")),
         {:ok, engineer_llm} <- LLM.parse(Keyword.get(opts, :engineer_model, "gpt-4.1")),
         {:ok, researcher_llm} <- LLM.parse(Keyword.get(opts, :researcher_model, "o3-mini")),
         {:ok, formatter_llm} <- LLM.parse(Keyword.get(opts, :formatter_model, "o3-mini")),
         {:ok, plan, persisted_step_outputs} <-
           prepare_run_state(
             context,
             client,
             session.keys,
             planner_llm,
             reviewer_llm,
             involved_agents,
             max_n_steps,
             restart_at_step,
             experiment_dir
           ),
         :ok <- maybe_reset_experiment_dir(experiment_dir, plan, restart_at_step),
         :ok <-
           Progress.emit(opts, %{
             kind: :progress,
             message: "Execution plan ready with #{length(plan.steps)} steps.",
             progress: 22,
             stage: "results:plan_ready"
           }),
         {:ok, step_outputs} <-
           run_steps(
             plan,
             plan.steps,
             context,
             client,
             executor,
             session.keys,
             engineer_llm,
             researcher_llm,
             max_n_attempts,
             restart_at_step,
             hardware_constraints,
             experiment_dir,
             persisted_step_outputs,
             opts
           ),
         final_prompt <- WorkflowPrompts.results_final_prompt(context, step_outputs),
         :ok <-
           Progress.emit(opts, %{
             kind: :progress,
             message: "Formatting the final results narrative.",
             progress: 86,
             stage: "results:finalize"
           }),
         {:ok, final_text} <- AI.complete(client, final_prompt, formatter_llm, session.keys),
         {:ok, results_block} <- Text.extract_block_or_fallback(final_text, "RESULTS") do
      log_path = Path.join(experiment_dir, "step_logs.md")
      File.mkdir_p!(experiment_dir)
      File.write!(log_path, render_step_log(plan.steps, step_outputs))

      Progress.emit(opts, %{
        kind: :finished,
        status: :success,
        message: "Results workflow finished and plots were collected.",
        progress: 94,
        stage: "results:complete"
      })

      {:ok,
       %{
         results: Text.clean_section(results_block, "RESULTS"),
         plot_paths: collect_plot_paths(step_outputs),
         plan: plan,
         step_outputs: step_outputs,
         log_path: log_path
       }}
    end
  end

  defp run_steps(
         plan,
         steps,
         context,
         client,
         executor,
         keys,
         engineer_llm,
         researcher_llm,
         max_n_attempts,
         restart_at_step,
         hardware_constraints,
         experiment_dir,
         persisted_step_outputs,
         opts
       ) do
    start_index = if restart_at_step < 0, do: 0, else: restart_at_step
    persisted_step_outputs = List.wrap(persisted_step_outputs)

    cond do
      start_index > length(steps) ->
        {:error, {:invalid_restart_at_step, start_index, length(steps)}}

      start_index > length(persisted_step_outputs) ->
        {:error, {:missing_restart_step_outputs, start_index, length(persisted_step_outputs)}}

      true ->
        initial_outputs = Enum.take(persisted_step_outputs, start_index)

        steps
        |> Enum.with_index()
        |> Enum.reduce_while({:ok, initial_outputs}, fn {step, index}, {:ok, outputs} ->
          if index < start_index do
            {:cont, {:ok, outputs}}
          else
            Progress.emit(opts, %{
              kind: :progress,
              message:
                "Running results step #{index + 1} of #{length(steps)}: #{Text.fetch(step, "goal")}",
              progress: step_progress(index, length(steps), 28, 78),
              stage: "results:step_start"
            })

            case run_single_step(
                   step,
                   context,
                   outputs,
                   client,
                   executor,
                   keys,
                   engineer_llm,
                   researcher_llm,
                   max_n_attempts,
                   hardware_constraints,
                   experiment_dir,
                   opts
                 ) do
              {:ok, step_output} ->
                updated_outputs = outputs ++ [step_output]
                persist_run_state(experiment_dir, plan, updated_outputs)

                Progress.emit(opts, %{
                  kind: :progress,
                  message: "Finished #{Text.fetch(step, "id")}: #{Text.fetch(step, "goal")}",
                  progress: step_progress(index + 1, length(steps), 30, 82),
                  stage: "results:step_complete"
                })

                {:cont, {:ok, updated_outputs}}

              {:error, reason} ->
                {:halt, {:error, reason}}
            end
          end
        end)
    end
  end

  defp run_single_step(
         step,
         context,
         outputs,
         client,
         executor,
         keys,
         engineer_llm,
         researcher_llm,
         max_n_attempts,
         hardware_constraints,
         experiment_dir,
         opts
       ) do
    needs_code = truthy?(Text.fetch(step, "needs_code"))
    agent = Text.fetch(step, "agent")

    cond do
      needs_code or agent == "engineer" ->
        run_engineer_step(
          step,
          context,
          outputs,
          client,
          executor,
          keys,
          engineer_llm,
          researcher_llm,
          max_n_attempts,
          hardware_constraints,
          experiment_dir,
          "",
          opts
        )

      true ->
        prompt = WorkflowPrompts.results_step_summary_prompt(step, context, outputs, "", "")

        with {:ok, response} <- AI.complete(client, prompt, researcher_llm, keys),
             {:ok, block} <- Text.extract_block_or_fallback(response, "STEP_OUTPUT") do
          {:ok,
           %{
             id: Text.fetch(step, "id"),
             agent: agent,
             goal: Text.fetch(step, "goal"),
             output: Text.clean_section(block, "STEP_OUTPUT"),
             execution_output: "",
             generated_files: []
           }}
        end
    end
  end

  defp run_engineer_step(
         step,
         context,
         outputs,
         client,
         executor,
         keys,
         engineer_llm,
         researcher_llm,
         max_n_attempts,
         hardware_constraints,
         experiment_dir,
         previous_error,
         opts,
         attempt \\ 1
       ) do
    if attempt > 1 do
      Progress.emit(opts, %{
        kind: :progress,
        message: "Retrying #{Text.fetch(step, "id")} after a failed execution attempt.",
        progress: 50,
        stage: "results:retry"
      })
    end

    prompt =
      WorkflowPrompts.results_engineer_prompt(
        step,
        context,
        outputs,
        previous_error,
        hardware_constraints
      )

    with {:ok, object} <-
           AI.generate_object(client, prompt, @engineer_schema, engineer_llm, keys),
         code when is_binary(code) and code != "" <- Text.fetch(object, "code") do
      case executor.execute(code,
             work_dir: experiment_dir,
             step_id: Text.fetch(step, "id"),
             attempt: attempt
           ) do
        {:ok, execution} ->
          execution_output = Text.fetch(execution, "output") || ""
          engineer_summary = Text.fetch(object, "summary") || ""

          summary_prompt =
            WorkflowPrompts.results_step_summary_prompt(
              step,
              context,
              outputs,
              engineer_summary,
              execution_output
            )

          with {:ok, response} <- AI.complete(client, summary_prompt, researcher_llm, keys),
               {:ok, block} <- Text.extract_block_or_fallback(response, "STEP_OUTPUT") do
            {:ok,
             %{
               id: Text.fetch(step, "id"),
               agent: Text.fetch(step, "agent"),
               goal: Text.fetch(step, "goal"),
               output: Text.clean_section(block, "STEP_OUTPUT"),
               execution_output: execution_output,
               generated_files: normalize_generated_files(Text.fetch(execution, "generated_files"))
             }}
          end

        {:error, execution} when attempt < max_n_attempts ->
          run_engineer_step(
            step,
            context,
            outputs,
            client,
            executor,
            keys,
            engineer_llm,
            researcher_llm,
            max_n_attempts,
            hardware_constraints,
            experiment_dir,
            Text.fetch(execution, "output") || inspect(execution),
            opts,
            attempt + 1
          )

        {:error, execution} ->
          {:error, {:results_step_failed, Text.fetch(step, "id"), execution}}
      end
    else
      {:error, reason} ->
        {:error, reason}

      _ ->
        {:error, {:invalid_engineer_response, step}}
    end
  end

  defp collect_plot_paths(step_outputs) do
    allowed_extensions = MapSet.new(["png", "jpg", "jpeg", "pdf", "svg"])

    step_outputs
    |> Enum.flat_map(fn output -> normalize_generated_files(Text.fetch(output, "generated_files")) end)
    |> Enum.filter(fn path ->
      is_binary(path) and
        path != "" and
        File.regular?(path) and
        (Path.extname(path) |> String.trim_leading(".") |> String.downcase()) in allowed_extensions
    end)
    |> Enum.uniq()
  end

  defp render_step_log(steps, outputs) do
    """
    # Results Workflow

    ## Planned Steps
    #{Enum.map_join(steps, "\n", fn step -> "- #{Text.fetch(step, "id")}: #{Text.fetch(step, "goal")}" end)}

    ## Step Outputs
    #{Enum.map_join(outputs, "\n\n", fn output -> """
      ### #{Text.fetch(output, "id")}
      Agent: #{Text.fetch(output, "agent")}
      Goal: #{Text.fetch(output, "goal")}

      #{Text.fetch(output, "output")}

      Execution output:
      ```
      #{Text.fetch(output, "execution_output")}
      ```
      """ end)}
    """
  end

  defp prepare_run_state(
         context,
         client,
         keys,
         planner_llm,
         reviewer_llm,
         involved_agents,
         max_n_steps,
         restart_at_step,
         experiment_dir
       )
       when restart_at_step < 0 do
    plan_new_run(
      context,
      client,
      keys,
      planner_llm,
      reviewer_llm,
      involved_agents,
      max_n_steps,
      experiment_dir
    )
  end

  defp prepare_run_state(
         context,
         client,
         keys,
         planner_llm,
         reviewer_llm,
         involved_agents,
         max_n_steps,
         0,
         experiment_dir
       ) do
    case load_run_state(experiment_dir) do
      {:ok, %{plan: plan, step_outputs: step_outputs}} ->
        {:ok, plan, step_outputs}

      {:error, :missing_results_run_state} ->
        plan_new_run(
          context,
          client,
          keys,
          planner_llm,
          reviewer_llm,
          involved_agents,
          max_n_steps,
          experiment_dir
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp prepare_run_state(
         _context,
         _client,
         _keys,
         _planner_llm,
         _reviewer_llm,
         _involved_agents,
         _max_n_steps,
         restart_at_step,
         experiment_dir
       ) do
    case load_run_state(experiment_dir) do
      {:ok, %{plan: plan, step_outputs: step_outputs}} ->
        {:ok, plan, step_outputs}

      {:error, :missing_results_run_state} ->
        {:error, {:missing_restart_state, run_state_path(experiment_dir), restart_at_step}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp plan_new_run(
         context,
         client,
         keys,
         planner_llm,
         reviewer_llm,
         involved_agents,
         max_n_steps,
         experiment_dir
       ) do
    with {:ok, plan} <-
           CMBAgentLoop.plan_and_review("results", context,
             client: client,
             keys: keys,
             planner_model: planner_llm,
             plan_reviewer_model: reviewer_llm,
             allowed_agents: involved_agents,
             max_steps: max_n_steps
           ) do
      persist_run_state(experiment_dir, plan, [])
      {:ok, plan, []}
    end
  end

  defp maybe_reset_experiment_dir(experiment_dir, plan, restart_at_step)
       when restart_at_step < 0 or restart_at_step == 0 do
    File.rm_rf!(experiment_dir)
    persist_run_state(experiment_dir, plan, [])
  end

  defp maybe_reset_experiment_dir(_experiment_dir, _plan, _restart_at_step), do: :ok

  defp persist_run_state(experiment_dir, plan, step_outputs) do
    File.mkdir_p!(experiment_dir)

    payload = %{
      "version" => 1,
      "plan" => serialize_plan(plan),
      "step_outputs" => Enum.map(step_outputs, &serialize_step_output/1)
    }

    File.write!(run_state_path(experiment_dir), Jason.encode!(payload, pretty: true))
    :ok
  end

  defp load_run_state(experiment_dir) do
    state_path = run_state_path(experiment_dir)

    if File.regular?(state_path) do
      with {:ok, raw_state_json} <- File.read(state_path),
           {:ok, raw_state} <- Jason.decode(raw_state_json),
           {:ok, plan} <- normalize_saved_plan(Text.fetch(raw_state, "plan")),
           {:ok, step_outputs} <-
             normalize_saved_step_outputs(Text.fetch(raw_state, "step_outputs")),
           :ok <- validate_saved_step_outputs(plan, step_outputs) do
        {:ok, %{plan: plan, step_outputs: step_outputs}}
      else
        _ -> {:error, {:invalid_results_run_state, state_path}}
      end
    else
      {:error, :missing_results_run_state}
    end
  end

  defp run_state_path(experiment_dir),
    do: Path.join(experiment_dir, "results_workflow_state.json")

  defp serialize_plan(plan) do
    %{
      "summary" => Map.get(plan, :summary, ""),
      "feedback" => Map.get(plan, :feedback, ""),
      "steps" => List.wrap(Map.get(plan, :steps, []))
    }
  end

  defp serialize_step_output(output) do
    %{
      "id" => Text.fetch(output, "id"),
      "agent" => Text.fetch(output, "agent"),
      "goal" => Text.fetch(output, "goal"),
      "output" => Text.fetch(output, "output"),
      "execution_output" => Text.fetch(output, "execution_output") || "",
      "generated_files" => normalize_generated_files(Text.fetch(output, "generated_files"))
    }
  end

  defp normalize_saved_plan(plan) when is_map(plan) do
    steps =
      plan
      |> Text.fetch("steps")
      |> List.wrap()
      |> Enum.map(&normalize_saved_step/1)

    summary = Text.fetch(plan, "summary") || ""
    feedback = Text.fetch(plan, "feedback") || ""

    if steps == [] or Enum.any?(steps, &is_nil/1) do
      {:error, :invalid_plan}
    else
      {:ok, %{summary: summary, feedback: feedback, steps: steps}}
    end
  end

  defp normalize_saved_plan(_plan), do: {:error, :invalid_plan}

  defp normalize_saved_step_outputs(outputs) when is_list(outputs) do
    normalized = Enum.map(outputs, &normalize_saved_step_output/1)

    if Enum.any?(normalized, &is_nil/1) do
      {:error, :invalid_step_outputs}
    else
      {:ok, normalized}
    end
  end

  defp normalize_saved_step_outputs(_outputs), do: {:error, :invalid_step_outputs}

  defp normalize_saved_step(step) when is_map(step) do
    id = Text.fetch(step, "id")
    agent = Text.fetch(step, "agent")
    goal = Text.fetch(step, "goal")
    deliverable = Text.fetch(step, "deliverable")

    if Enum.any?([id, agent, goal, deliverable], &(&1 in [nil, ""])) do
      nil
    else
      %{
        "id" => id,
        "agent" => agent,
        "goal" => goal,
        "deliverable" => deliverable,
        "needs_code" => truthy?(Text.fetch(step, "needs_code"))
      }
    end
  end

  defp normalize_saved_step(_step), do: nil

  defp normalize_saved_step_output(output) when is_map(output) do
    id = Text.fetch(output, "id")
    agent = Text.fetch(output, "agent")
    goal = Text.fetch(output, "goal")
    body = Text.fetch(output, "output")

    if Enum.any?([id, agent, goal, body], &(&1 in [nil, ""])) do
      nil
    else
      %{
        "id" => id,
        "agent" => agent,
        "goal" => goal,
        "output" => body,
        "execution_output" => Text.fetch(output, "execution_output") || "",
        "generated_files" => normalize_generated_files(Text.fetch(output, "generated_files"))
      }
    end
  end

  defp normalize_saved_step_output(_output), do: nil

  defp normalize_generated_files(files) when is_list(files) do
    files
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
  end

  defp normalize_generated_files(_files), do: []

  defp validate_saved_step_outputs(plan, step_outputs) do
    plan_step_ids = Enum.map(plan.steps, &Text.fetch(&1, "id"))
    saved_step_ids = Enum.map(step_outputs, &Text.fetch(&1, "id"))

    valid? =
      length(saved_step_ids) <= length(plan_step_ids) and
        Enum.zip(saved_step_ids, plan_step_ids)
        |> Enum.all?(fn {saved_step_id, plan_step_id} -> saved_step_id == plan_step_id end)

    if valid?, do: :ok, else: {:error, :mismatched_step_outputs}
  end

  defp truthy?(value) when value in [true, "true", "TRUE", 1], do: true
  defp truthy?(_value), do: false

  defp step_progress(_index, total, min_progress, max_progress) when total <= 0 do
    max(min_progress, max_progress)
  end

  defp step_progress(index, total, min_progress, max_progress) do
    span = max_progress - min_progress
    min_progress + round(index / total * span)
  end
end
