alias DenarioEx

defmodule DenarioExDemo.OfflineClient do
  @behaviour DenarioEx.LLMClient

  @impl true
  def complete([%{role: "user", content: prompt}], _opts) do
    cond do
      String.contains?(
        prompt,
        "Your goal is to generate a groundbreaking idea for a scientific paper."
      ) ->
        {:ok,
         """
         \\begin{IDEA}
         Interpretable anomaly detection for urban microclimate sensor networks.
         \\end{IDEA}
         """}

      String.contains?(prompt, "Your goal is to critic an idea.") ->
        {:ok,
         """
         \\begin{CRITIC}
         Tighten the scope around one anomaly-detection task and one temporally blocked evaluation protocol.
         \\end{CRITIC}
         """}

      String.contains?(
        prompt,
        "Your task is to think about the methods to use in order to carry it out."
      ) ->
        {:ok,
         """
         \\begin{METHODS}
         1. Align and clean the sensor streams.
         2. Build blocked temporal train-validation-test splits.
         3. Train an interpretable anomaly detector and compare it against simple baselines.
         4. Report discrimination, stability, and calibration diagnostics.
         \\end{METHODS}
         """}

      String.contains?(prompt, "[DENARIO_RESULTS_STEP_SUMMARY]") ->
        {:ok,
         """
         \\begin{STEP_OUTPUT}
         The engineer produced reproducible summary statistics and saved one anomaly-score distribution plot.
         \\end{STEP_OUTPUT}
         """}

      String.contains?(prompt, "[DENARIO_RESULTS_FINAL]") ->
        {:ok,
         """
         \\begin{RESULTS}
         The anomaly detector achieved stable performance across blocked temporal splits and produced a clear anomaly-score distribution plot. The synthetic run shows strong separation between nominal and anomalous regimes, supporting the project idea.
         \\end{RESULTS}
         """}

      String.contains?(prompt, "[DENARIO_LITERATURE_SUMMARY]") ->
        {:ok,
         """
         \\begin{SUMMARY}
         The retrieved literature overlaps with urban environmental sensing and anomaly monitoring broadly, but it does not match the exact interpretable anomaly-detection framing or evaluation setup proposed here. The idea can be considered novel relative to the selected sources.
         \\end{SUMMARY}
         """}

      String.contains?(prompt, "[DENARIO_PAPER_KEYWORDS]") ->
        {:ok,
         """
         \\begin{KEYWORDS}
         anomaly detection, urban climate, sensor networks, interpretable models, time-series analysis
         \\end{KEYWORDS}
         """}

      String.contains?(prompt, "[DENARIO_PAPER_SECTION][Introduction]") ->
        {:ok,
         """
         \\begin{INTRODUCTION}
         Urban microclimate monitoring remains difficult because dense low-cost sensor networks produce noisy, drifting time-series and anomalies are rare. This workflow frames the problem as interpretable anomaly detection over temporally aligned sensor streams and motivates why stable detection matters for urban operations.
         \\end{INTRODUCTION}
         """}

      String.contains?(prompt, "[DENARIO_PAPER_SECTION][Methods]") ->
        {:ok,
         """
         \\begin{METHODS}
         We align, clean, and calibrate the sensor streams before training an interpretable anomaly detector over blocked temporal splits. We compare against simple baselines and evaluate both discrimination and calibration behavior.
         \\end{METHODS}
         """}

      String.contains?(prompt, "[DENARIO_PAPER_SECTION][Results]") ->
        {:ok,
         """
         \\begin{RESULTS}
         The proposed detector provides consistent separation between nominal and anomalous conditions and remains stable across blocked temporal evaluation. The generated diagnostic plot highlights the operating region used for interpretation.
         \\end{RESULTS}
         """}

      String.contains?(prompt, "[DENARIO_PAPER_SECTION][Conclusions]") ->
        {:ok,
         """
         \\begin{CONCLUSIONS}
         Interpretable anomaly detection over dense urban microclimate sensor streams is feasible with careful temporal evaluation and calibration-aware reporting. This offline demo shows the complete artifact flow from idea to paper draft.
         \\end{CONCLUSIONS}
         """}

      String.contains?(prompt, "[DENARIO_PAPER_FIGURE_CAPTION]") ->
        {:ok,
         """
         \\begin{CAPTION}
         Distribution of anomaly scores across the evaluation split, highlighting separation between nominal and anomalous conditions.
         \\end{CAPTION}
         """}

      String.contains?(prompt, "[DENARIO_PAPER_REFINE_RESULTS]") ->
        {:ok,
         """
         \\begin{RESULTS}
         The proposed detector provides consistent separation between nominal and anomalous conditions and remains stable across blocked temporal evaluation. Figure \\ref{fig:anomaly_scores} visualizes the anomaly-score distribution used in the interpretation.
         \\begin{figure}[t]
         \\centering
         \\includegraphics[width=0.48\\textwidth]{anomaly_scores.png}
         \\caption{Distribution of anomaly scores across the evaluation split, highlighting separation between nominal and anomalous conditions.}
         \\label{fig:anomaly_scores}
         \\end{figure}
         \\end{RESULTS}
         """}

      true ->
        {:error, {:unexpected_prompt, prompt}}
    end
  end

  @impl true
  def generate_object([%{role: "user", content: prompt}], _schema, _opts) do
    cond do
      String.contains?(prompt, "[DENARIO_PLAN][results]") ->
        {:ok,
         %{
           "summary" => "Run one engineering step and summarize the findings.",
           "steps" => [
             %{
               "id" => "results_1",
               "agent" => "engineer",
               "goal" => "Run the core analysis and generate one diagnostic plot",
               "deliverable" => "Reproducible code, console output, and one plot",
               "needs_code" => true
             },
             %{
               "id" => "results_2",
               "agent" => "researcher",
               "goal" => "Summarize the quantitative findings",
               "deliverable" => "Narrative summary of the evidence",
               "needs_code" => false
             }
           ]
         }}

      String.contains?(prompt, "[DENARIO_PLAN_REVIEW]") ->
        {:ok, %{"approved" => true, "feedback" => "The plan is focused and feasible."}}

      String.contains?(prompt, "[DENARIO_RESULTS_ENGINEER]") ->
        {:ok,
         %{
           "summary" => "Generate a simple deterministic analysis script.",
           "notes" => "Offline demo analysis.",
           "code" => "print('mean_score=0.91')\nprint('saved_plot=anomaly_scores.png')\n"
         }}

      String.contains?(prompt, "[DENARIO_LITERATURE_DECISION]") and
          String.contains?(prompt, "Round: 0") ->
        {:ok,
         %{
           "reason" =>
             "The first round should gather a focused literature set before making a novelty claim.",
           "decision" => "query",
           "query" => "urban microclimate anomaly detection low-cost sensor network"
         }}

      String.contains?(prompt, "[DENARIO_LITERATURE_DECISION]") ->
        {:ok,
         %{
           "reason" =>
             "The selected papers discuss urban sensing and anomaly monitoring, but none matches the exact interpretable framing and evaluation setup proposed here.",
           "decision" => "novel",
           "query" => ""
         }}

      String.contains?(prompt, "[DENARIO_LITERATURE_SELECT]") ->
        {:ok,
         %{
           "selected_paper_ids" => ["paper-123"],
           "rationale" => "This paper is the closest prior work in both task and domain."
         }}

      String.contains?(prompt, "[DENARIO_PAPER_ABSTRACT]") ->
        {:ok,
         %{
           "title" => "Interpretable Anomaly Detection for Urban Microclimate Sensor Networks",
           "abstract" =>
             "We study interpretable anomaly detection over dense urban microclimate sensor networks. Using temporally blocked evaluation and calibration-aware reporting, this offline workflow produces a complete research artifact chain from idea to paper draft."
         }}

      true ->
        {:error, {:unexpected_object_prompt, prompt}}
    end
  end
end

defmodule DenarioExDemo.OfflineExecutor do
  @behaviour DenarioEx.CodeExecutor

  @png_base64 "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9WnSUs8AAAAASUVORK5CYII="

  @impl true
  def execute(_code, opts) do
    work_dir = Keyword.fetch!(opts, :work_dir)
    File.mkdir_p!(work_dir)

    plot_path = Path.join(work_dir, "anomaly_scores.png")
    File.write!(plot_path, Base.decode64!(@png_base64))

    {:ok,
     %{
       "status" => 0,
       "output" => "mean_score=0.91\nsaved_plot=anomaly_scores.png",
       "generated_files" => [plot_path]
     }}
  end
end

defmodule DenarioExDemo.OfflineLiteratureClient do
  @behaviour DenarioEx.SemanticScholarClient

  @impl true
  def search(_query, _keys, _opts) do
    {:ok,
     %{
       "total" => 2,
       "data" => [
         %{
           "paperId" => "paper-123",
           "title" => "Urban sensing for anomaly monitoring",
           "year" => 2024,
           "citationCount" => 37,
           "abstract" =>
             "A broad study of anomaly monitoring in urban environmental sensor systems.",
           "url" => "https://example.com/paper-123",
           "authors" => [%{"name" => "A. Researcher"}, %{"name" => "B. Scientist"}],
           "externalIds" => %{"ArXiv" => "2401.12345"},
           "openAccessPdf" => %{"url" => "https://example.com/paper-123.pdf"}
         },
         %{
           "paperId" => "paper-456",
           "title" => "Benchmarking anomaly detectors for industrial telemetry",
           "year" => 2023,
           "citationCount" => 52,
           "abstract" =>
             "A benchmark paper on industrial telemetry anomaly detection with limited relevance to urban microclimate sensing.",
           "url" => "https://example.com/paper-456",
           "authors" => [%{"name" => "C. Analyst"}],
           "externalIds" => %{"DOI" => "10.1000/example"},
           "openAccessPdf" => %{"url" => "https://example.com/paper-456.pdf"}
         }
       ]
     }}
  end
end

defmodule DenarioExDemo do
  def run do
    project_dir =
      System.get_env("DENARIO_EX_DEMO_DIR") ||
        Path.join(System.tmp_dir!(), "denario_ex_offline_demo")

    with {:ok, denario} <- DenarioEx.new(project_dir: project_dir, clear_project_dir: true),
         {:ok, denario} <- DenarioEx.set_data_description(denario, data_description()),
         {:ok, denario} <-
           DenarioEx.get_idea_fast(
             denario,
             client: DenarioExDemo.OfflineClient,
             llm: "openai:gpt-4.1-mini",
             iterations: 2
           ),
         {:ok, denario} <-
           DenarioEx.get_method_fast(
             denario,
             client: DenarioExDemo.OfflineClient,
             llm: "openai:gpt-4.1-mini"
           ),
         {:ok, denario} <-
           DenarioEx.get_results(
             denario,
             client: DenarioExDemo.OfflineClient,
             executor: DenarioExDemo.OfflineExecutor,
             planner_model: "openai:gpt-4.1-mini",
             plan_reviewer_model: "openai:gpt-4.1-mini",
             engineer_model: "openai:gpt-4.1-mini",
             researcher_model: "openai:gpt-4.1-mini",
             formatter_model: "openai:gpt-4.1-mini",
             max_n_attempts: 1
           ),
         {:ok, denario} <-
           DenarioEx.check_idea(
             denario,
             client: DenarioExDemo.OfflineClient,
             semantic_scholar_client: DenarioExDemo.OfflineLiteratureClient,
             llm: "openai:gpt-4.1-mini",
             max_iterations: 3
           ),
         {:ok, denario} <-
           DenarioEx.get_paper(
             denario,
             client: DenarioExDemo.OfflineClient,
             llm: "openai:gpt-4.1-mini",
             writer: "climate scientist",
             journal: :neurips,
             add_citations: true,
             compile: false
           ) do
      print_summary(denario, project_dir)
    else
      {:error, reason} ->
        IO.puts(:stderr, "offline demo failed: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp data_description do
    """
    Analyze a tiny hypothetical urban microclimate dataset collected from dense low-cost sensor nodes.
    The project should propose one interpretable anomaly-detection direction, produce one diagnostic plot,
    compare nominal and anomalous regimes, and end with a short paper draft.
    """
  end

  defp print_summary(denario, project_dir) do
    files = [
      Path.join(project_dir, "input_files/data_description.md"),
      Path.join(project_dir, "input_files/idea.md"),
      Path.join(project_dir, "input_files/methods.md"),
      Path.join(project_dir, "input_files/results.md"),
      Path.join(project_dir, "input_files/literature.md"),
      Path.join(project_dir, "input_files/plots/anomaly_scores.png"),
      denario.research.paper_tex_path
    ]

    IO.puts("""
    Offline demo completed.

    Project directory: #{project_dir}
    Idea: #{excerpt(denario.research.idea)}
    Methods: #{excerpt(denario.research.methodology)}
    Results: #{excerpt(denario.research.results)}
    Literature sources: #{length(denario.research.literature_sources)}

    Generated files:
    #{Enum.map_join(files, "\n", &"- #{&1}")}
    """)
  end

  defp excerpt(text) do
    text
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, 120)
  end
end

DenarioExDemo.run()
