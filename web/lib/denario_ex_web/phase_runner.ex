defmodule DenarioExUI.PhaseRunner do
  @moduledoc false

  alias DenarioEx
  alias DenarioExUI.Projects

  @spec start(pid(), String.t(), String.t(), map()) :: {:ok, pid()} | {:error, term()}
  def start(live_view_pid, project_dir, phase, settings) do
    Task.Supervisor.start_child(DenarioExUI.TaskSupervisor, fn ->
      send(live_view_pid, {:phase_started, phase})
      send(live_view_pid, {:phase_finished, phase, run(project_dir, phase, settings)})
    end)
  end

  defp run(project_dir, phase, settings) do
    with {:ok, session} <- DenarioEx.new(project_dir: Path.expand(project_dir)),
         {:ok, updated} <- run_phase(session, phase, settings) do
      {:ok, Projects.snapshot(updated), success_message(phase)}
    end
  rescue
    exception ->
      {:error, Exception.message(exception)}
  end

  defp run_phase(session, "research_pilot", settings) do
    DenarioEx.research_pilot(
      session,
      nil,
      idea: [llm: model(settings)],
      method: [llm: model(settings)],
      results: [llm: model(settings)],
      literature: [llm: model(settings), mode: literature_mode(settings)],
      paper: [llm: model(settings), journal: journal(settings), compile: compile_paper?(settings)]
    )
  end

  defp run_phase(session, "enhance_data_description", settings) do
    DenarioEx.enhance_data_description(
      session,
      summarizer_model: model(settings),
      summarizer_response_formatter_model: model(settings)
    )
  end

  defp run_phase(session, "get_idea", settings),
    do: DenarioEx.get_idea(session, mode: :fast, llm: model(settings))

  defp run_phase(session, "get_method", settings),
    do: DenarioEx.get_method(session, mode: :fast, llm: model(settings))

  defp run_phase(session, "get_results", settings),
    do: DenarioEx.get_results(session, llm: model(settings))

  defp run_phase(session, "check_idea", settings),
    do: DenarioEx.check_idea(session, llm: model(settings), mode: literature_mode(settings))

  defp run_phase(session, "get_keywords", settings) do
    DenarioEx.get_keywords(
      session,
      nil,
      llm: model(settings),
      kw_type: keyword_taxonomy(settings),
      n_keywords: 5
    )
  end

  defp run_phase(session, "get_paper", settings) do
    DenarioEx.get_paper(
      session,
      llm: model(settings),
      journal: journal(settings),
      compile: compile_paper?(settings)
    )
  end

  defp run_phase(session, "referee", settings),
    do: DenarioEx.referee(session, llm: model(settings))

  defp run_phase(_session, phase, _settings), do: {:error, {:unsupported_phase, phase}}

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
end
