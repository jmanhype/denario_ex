defmodule DenarioExUI.PhaseRunner do
  @moduledoc false

  alias DenarioEx
  alias DenarioExUI.{PhaseEvents, PhaseRuns, Projects}

  @spec start(pid(), String.t(), String.t(), map()) :: {:ok, pid()} | {:error, term()}
  def start(_live_view_pid, project_dir, phase, settings) do
    run_id = PhaseEvents.new_run_id()
    expanded_dir = Path.expand(project_dir)

    case Task.Supervisor.start_child(DenarioExUI.TaskSupervisor, fn ->
           emit(expanded_dir, run_id, phase, %{
             status: :running,
             kind: :started,
             progress: 3,
             message: "#{Projects.phase_label(phase)} started.",
             stage: "#{phase}:start"
           })

           _ = run(expanded_dir, phase, settings, run_id)
         end) do
      {:ok, pid} ->
        PhaseRuns.put(run_id, %{
          pid: pid,
          project_dir: expanded_dir,
          phase: phase,
          settings: settings
        })

        {:ok, run_id}

      {:error, _reason} = error ->
        error
    end
  end

  @spec cancel(String.t()) :: :ok | {:error, term()}
  def cancel(run_id) do
    case PhaseRuns.get(run_id) do
      nil ->
        {:error, :unknown_run}

      %{pid: pid, project_dir: project_dir, phase: phase} = _record ->
        case DynamicSupervisor.terminate_child(DenarioExUI.TaskSupervisor, pid) do
          :ok ->
            :ok

          {:error, :not_found} ->
            if Process.alive?(pid), do: Process.exit(pid, :kill)

          _ ->
            :ok
        end

        PhaseRuns.delete(run_id)

        emit(project_dir, run_id, phase, %{
          status: :cancelled,
          kind: :finished,
          progress: 100,
          message: "#{Projects.phase_label(phase)} cancelled.",
          stage: "#{phase}:cancelled"
        })

        :ok
    end
  end

  defp run(project_dir, phase, settings, run_id) do
    emit(project_dir, run_id, phase, %{
      status: :running,
      kind: :progress,
      progress: 6,
      message: "Loading project state from disk.",
      stage: "#{phase}:load"
    })

    with {:ok, session} <- DenarioEx.new(project_dir: project_dir),
         {:ok, updated} <- run_phase(session, phase, settings, project_dir, run_id) do
      snapshot = Projects.snapshot(updated)
      message = success_message(phase)

      emit(project_dir, run_id, phase, %{
        status: :success,
        kind: :finished,
        progress: 100,
        message: message,
        stage: "#{phase}:complete",
        snapshot: snapshot
      })

      PhaseRuns.delete(run_id)
      {:ok, snapshot, message}
    else
      {:error, reason} = error ->
        emit(project_dir, run_id, phase, %{
          status: :error,
          kind: :finished,
          progress: 100,
          message: "#{Projects.phase_label(phase)} failed: #{error_message(reason)}",
          stage: "#{phase}:error"
        })

        PhaseRuns.delete(run_id)
        error
    end
  rescue
    exception ->
      message = Exception.message(exception)

      emit(project_dir, run_id, phase, %{
        status: :error,
        kind: :finished,
        progress: 100,
        message: "#{Projects.phase_label(phase)} failed: #{message}",
        stage: "#{phase}:error"
      })

      PhaseRuns.delete(run_id)
      {:error, message}
  end

  defp run_phase(session, "research_pilot", settings, project_dir, run_id) do
    [
      {"get_idea", "Generating the research idea.", 8, 24},
      {"get_method", "Drafting the methodology.", 24, 40},
      {"get_results", "Executing the results workflow.", 40, 72},
      {"check_idea", "Running the literature check.", 72, 84},
      {"get_paper", "Writing the paper draft.", 84, 97}
    ]
    |> Enum.reduce_while({:ok, session}, fn {subphase, message, min_progress, max_progress},
                                            {:ok, current_session} ->
      emit(project_dir, run_id, "research_pilot", %{
        status: :running,
        kind: :progress,
        progress: min_progress,
        message: message,
        stage: "research_pilot:#{subphase}",
        metadata: %{subphase: subphase}
      })

      callback =
        nested_progress_callback(
          project_dir,
          run_id,
          "research_pilot",
          subphase,
          min_progress,
          max_progress
        )

      case invoke_phase(current_session, subphase, settings, callback) do
        {:ok, updated_session} -> {:cont, {:ok, updated_session}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp run_phase(session, phase, settings, project_dir, run_id) do
    callback = phase_progress_callback(project_dir, run_id, phase)
    invoke_phase(session, phase, settings, callback)
  end

  defp invoke_phase(session, "enhance_data_description", settings, callback) do
    DenarioEx.enhance_data_description(
      session,
      summarizer_model: model(settings),
      summarizer_response_formatter_model: model(settings),
      progress_callback: callback
    )
  end

  defp invoke_phase(session, "get_idea", settings, callback) do
    DenarioEx.get_idea(session,
      mode: :fast,
      llm: model(settings),
      progress_callback: callback
    )
  end

  defp invoke_phase(session, "get_method", settings, callback) do
    DenarioEx.get_method(session,
      mode: :fast,
      llm: model(settings),
      progress_callback: callback
    )
  end

  defp invoke_phase(session, "get_results", settings, callback) do
    DenarioEx.get_results(session,
      llm: model(settings),
      progress_callback: callback
    )
  end

  defp invoke_phase(session, "check_idea", settings, callback) do
    DenarioEx.check_idea(session,
      llm: model(settings),
      mode: literature_mode(settings),
      progress_callback: callback
    )
  end

  defp invoke_phase(session, "get_keywords", settings, callback) do
    DenarioEx.get_keywords(
      session,
      nil,
      llm: model(settings),
      kw_type: keyword_taxonomy(settings),
      n_keywords: 5,
      progress_callback: callback
    )
  end

  defp invoke_phase(session, "get_paper", settings, callback) do
    DenarioEx.get_paper(
      session,
      llm: model(settings),
      journal: journal(settings),
      compile: compile_paper?(settings),
      progress_callback: callback
    )
  end

  defp invoke_phase(session, "referee", settings, callback) do
    DenarioEx.referee(session,
      llm: model(settings),
      progress_callback: callback
    )
  end

  defp invoke_phase(_session, phase, _settings, _callback),
    do: {:error, {:unsupported_phase, phase}}

  defp phase_progress_callback(project_dir, run_id, phase) do
    fn event ->
      emit(project_dir, run_id, phase, event)
    end
  end

  defp nested_progress_callback(project_dir, run_id, phase, subphase, min_progress, max_progress) do
    fn event ->
      emit(project_dir, run_id, phase, %{
        status: Map.get(event, :status, :running),
        kind: Map.get(event, :kind, :progress),
        progress:
          remap_progress(Map.get(event, :progress, min_progress), min_progress, max_progress),
        message: Map.get(event, :message, Projects.phase_label(subphase)),
        stage: Map.get(event, :stage, "#{phase}:#{subphase}"),
        metadata: %{subphase: subphase}
      })
    end
  end

  defp emit(project_dir, run_id, phase, attrs) do
    PhaseEvents.broadcast(project_dir, Map.merge(attrs, %{run_id: run_id, phase: phase}))
  end

  defp remap_progress(progress, min_progress, max_progress) do
    normalized =
      case progress do
        value when is_integer(value) -> min(max(value, 0), 100)
        value when is_float(value) -> value |> round() |> min(100) |> max(0)
        _ -> 0
      end

    min_progress + round(normalized / 100 * (max_progress - min_progress))
  end

  defp model(settings), do: Map.get(settings, "llm", "openai:gpt-4.1-mini")

  defp literature_mode(settings) do
    case Map.get(settings, "literature_mode", "semantic_scholar") do
      "futurehouse" -> :futurehouse
      _ -> :semantic_scholar
    end
  end

  defp keyword_taxonomy(settings) do
    case Map.get(settings, "keyword_taxonomy", "unesco") do
      "aas" -> :aas
      "aaai" -> :aaai
      _ -> :unesco
    end
  end

  defp journal(settings) do
    case Map.get(settings, "journal", "none") do
      "aas" -> :aas
      "aps" -> :aps
      "icml" -> :icml
      "jhep" -> :jhep
      "neurips" -> :neurips
      "pasj" -> :pasj
      _ -> :none
    end
  end

  defp compile_paper?(settings) do
    Map.get(settings, "compile_paper", "false") in [true, "true", "on", "1"]
  end

  defp success_message("research_pilot"), do: "Full workflow completed."
  defp success_message("enhance_data_description"), do: "Data description enhanced."
  defp success_message("get_idea"), do: "Idea generated."
  defp success_message("get_method"), do: "Methodology generated."
  defp success_message("get_results"), do: "Results and plots generated."
  defp success_message("check_idea"), do: "Literature check completed."
  defp success_message("get_keywords"), do: "Keywords extracted."
  defp success_message("get_paper"), do: "Paper artifact updated."
  defp success_message("referee"), do: "Referee review completed."
  defp success_message(_phase), do: "Phase completed."

  defp error_message(reason) when is_binary(reason), do: reason
  defp error_message(reason), do: inspect(reason)
end
