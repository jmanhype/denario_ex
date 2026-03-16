defmodule DenarioExUI.Projects do
  @moduledoc false

  alias DenarioEx
  alias DenarioEx.ArtifactRegistry

  @editable_sections [
    %{
      key: "data_description",
      label: "Data Description",
      helper: "Describe the dataset, the observables, and the scientific context."
    },
    %{
      key: "idea",
      label: "Idea",
      helper: "The core paper idea or hypothesis the workflow will push forward."
    },
    %{
      key: "methodology",
      label: "Methodology",
      helper: "The planned method, experiment, or analysis protocol."
    },
    %{
      key: "results",
      label: "Results",
      helper: "Execution output, statistical findings, and figure-ready narrative."
    },
    %{
      key: "literature",
      label: "Literature",
      helper: "Novelty checks, precedent findings, and citation guidance."
    },
    %{
      key: "referee_report",
      label: "Referee Report",
      helper: "Reviewer-style critique of the current paper or draft content."
    }
  ]

  @phase_specs [
    %{
      key: "research_pilot",
      label: "Run Full Workflow",
      description: "Idea, method, results, literature, and paper in one pass.",
      requires: ["data_description"]
    },
    %{
      key: "enhance_data_description",
      label: "Enhance Description",
      description: "Rewrite the data description into a cleaner scientific brief.",
      requires: ["data_description"]
    },
    %{
      key: "get_idea",
      label: "Generate Idea",
      description: "Draft the paper idea from the current data description.",
      requires: ["data_description"]
    },
    %{
      key: "get_method",
      label: "Generate Method",
      description: "Produce the methods section or experimental approach.",
      requires: ["data_description", "idea"]
    },
    %{
      key: "get_results",
      label: "Generate Results",
      description: "Run the results workflow and write figures to disk.",
      requires: ["data_description", "idea", "methodology"]
    },
    %{
      key: "check_idea",
      label: "Literature Check",
      description: "Run novelty checking via Semantic Scholar/OpenAlex or FutureHouse.",
      requires: ["data_description", "idea"]
    },
    %{
      key: "get_keywords",
      label: "Extract Keywords",
      description: "Generate taxonomy-backed keywords for the current work.",
      requires: ["idea", "methodology", "results"]
    },
    %{
      key: "get_paper",
      label: "Generate Paper",
      description: "Write the paper draft and optionally compile the PDF.",
      requires: ["idea", "methodology", "results"]
    },
    %{
      key: "referee",
      label: "Referee Review",
      description: "Review the paper PDF or fall back to the source text.",
      requires_any: ["paper_pdf", "paper_tex", "results"]
    }
  ]

  @default_settings %{
    "llm" => "openai:gpt-4.1-mini",
    "literature_mode" => "semantic_scholar",
    "keyword_taxonomy" => "unesco",
    "journal" => "none",
    "compile_paper" => "false"
  }

  @spec default_settings() :: map()
  def default_settings, do: @default_settings

  @spec editable_sections() :: [map()]
  def editable_sections, do: @editable_sections

  @spec phase_specs(map() | nil) :: [map()]
  def phase_specs(nil), do: Enum.map(@phase_specs, &Map.put(&1, :ready, false))

  def phase_specs(snapshot) when is_map(snapshot) do
    Enum.map(@phase_specs, fn spec ->
      Map.put(spec, :ready, ready_for_phase?(snapshot, spec))
    end)
  end

  @spec phase_label(String.t()) :: String.t()
  def phase_label(phase_key) do
    case Enum.find(@phase_specs, &(&1.key == phase_key)) do
      nil -> phase_key
      spec -> spec.label
    end
  end

  @spec load(String.t()) :: {:ok, map()} | {:error, term()}
  def load(project_dir) do
    with {:ok, expanded} <- normalize_project_dir(project_dir),
         {:ok, session} <- DenarioEx.new(project_dir: expanded) do
      {:ok, snapshot(session)}
    end
  end

  @spec save_artifact(String.t(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def save_artifact(project_dir, artifact_name, value) do
    with {:ok, session} <- load_session(project_dir),
         {:ok, updated} <- do_save_artifact(session, artifact_name, value) do
      {:ok, snapshot(updated)}
    end
  end

  @spec snapshot(DenarioEx.t()) :: map()
  def snapshot(%DenarioEx{} = session) do
    research = session.research
    artifact_values = artifact_values(research)

    referee_log_path =
      Path.join(ArtifactRegistry.referee_output_dir(session.project_dir), "referee.log")

    %{
      project_dir: session.project_dir,
      input_files_dir: session.input_files_dir,
      plots_dir: session.plots_dir,
      paper_dir: ArtifactRegistry.paper_dir(session.project_dir),
      referee_output_dir: ArtifactRegistry.referee_output_dir(session.project_dir),
      artifact_values: artifact_values,
      artifact_presence:
        Map.new(artifact_values, fn {key, content} -> {key, present?(content)} end),
      plot_paths: research.plot_paths,
      paper_tex_path: research.paper_tex_path,
      paper_pdf_path: research.paper_pdf_path,
      referee_log_path: if(File.regular?(referee_log_path), do: referee_log_path, else: nil),
      literature_source_count: length(research.literature_sources),
      keywords_count: keyword_count(research.keywords),
      keywords_preview: DenarioEx.show_keywords(session),
      available_outputs: %{
        "paper_tex" => file_exists?(research.paper_tex_path),
        "paper_pdf" => file_exists?(research.paper_pdf_path),
        "results" => present?(research.results)
      }
    }
  end

  defp load_session(project_dir) do
    with {:ok, expanded} <- normalize_project_dir(project_dir) do
      DenarioEx.new(project_dir: expanded)
    end
  end

  defp normalize_project_dir(project_dir) when is_binary(project_dir) do
    cleaned = String.trim(project_dir)

    if cleaned == "" do
      {:error, :missing_project_dir}
    else
      {:ok, Path.expand(cleaned)}
    end
  end

  defp normalize_project_dir(_project_dir), do: {:error, :missing_project_dir}

  defp do_save_artifact(session, "data_description", value),
    do: DenarioEx.set_data_description(session, value)

  defp do_save_artifact(session, "idea", value), do: DenarioEx.set_idea(session, value)
  defp do_save_artifact(session, "methodology", value), do: DenarioEx.set_method(session, value)
  defp do_save_artifact(session, "results", value), do: DenarioEx.set_results(session, value)

  defp do_save_artifact(session, "literature", value),
    do: DenarioEx.set_literature(session, value)

  defp do_save_artifact(session, "referee_report", value) do
    ArtifactRegistry.write_text(session.project_dir, :referee_report, value)
    {:ok, %{session | research: %{session.research | referee_report: value}}}
  end

  defp do_save_artifact(_session, artifact_name, _value),
    do: {:error, {:unknown_artifact, artifact_name}}

  defp artifact_values(research) do
    %{
      "data_description" => research.data_description,
      "idea" => research.idea,
      "methodology" => research.methodology,
      "results" => research.results,
      "literature" => research.literature,
      "referee_report" => research.referee_report
    }
  end

  defp ready_for_phase?(snapshot, spec) do
    requires = Map.get(spec, :requires, [])
    requires_any = Map.get(spec, :requires_any, [])

    Enum.all?(requires, &present_key?(snapshot, &1)) and
      (requires_any == [] or Enum.any?(requires_any, &present_key?(snapshot, &1)))
  end

  defp present_key?(snapshot, key) do
    Map.get(snapshot.artifact_presence, key, false) ||
      Map.get(snapshot.available_outputs, key, false)
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(nil), do: false
  defp present?([]), do: false
  defp present?(%{} = map), do: map_size(map) > 0
  defp present?(value) when is_list(value), do: value != []
  defp present?(_value), do: true

  defp file_exists?(path) when is_binary(path), do: File.regular?(path)
  defp file_exists?(_path), do: false

  defp keyword_count(keywords) when is_map(keywords), do: map_size(keywords)
  defp keyword_count(keywords) when is_list(keywords), do: length(keywords)
  defp keyword_count(_keywords), do: 0
end
