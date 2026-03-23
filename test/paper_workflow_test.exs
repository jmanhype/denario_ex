defmodule DenarioEx.PaperWorkflowTest do
  use ExUnit.Case, async: true

  alias DenarioEx

  defmodule LatexSafeClient do
    @behaviour DenarioEx.LLMClient

    @impl true
    def complete([%{role: "user", content: prompt}], _opts) do
      cond do
        String.contains?(prompt, "[DENARIO_PAPER_KEYWORDS]") ->
          {:ok, "\\begin{KEYWORDS}feature_3, anomaly detection\\end{KEYWORDS}"}

        String.contains?(prompt, "[DENARIO_PAPER_SECTION][Introduction]") ->
          {:ok,
           "\\begin{INTRODUCTION}We study feature_3 on a small dataset with 95% confidence summaries.\\end{INTRODUCTION}"}

        String.contains?(prompt, "[DENARIO_PAPER_SECTION][Methods]") ->
          {:ok,
           "\\begin{METHODS}The method tracks feature_3 under repeated measurements and reports 95% intervals.\\end{METHODS}"}

        String.contains?(prompt, "[DENARIO_PAPER_SECTION][Results]") ->
          {:ok,
           "\\begin{RESULTS}Raw results reference feature_3 before figure insertion.\\end{RESULTS}"}

        String.contains?(prompt, "[DENARIO_PAPER_SECTION][Conclusions]") ->
          {:ok,
           "\\begin{CONCLUSIONS}Feature_3 remains the dominant explanatory signal in 95% of runs.\\end{CONCLUSIONS}"}

        String.contains?(prompt, "[DENARIO_PAPER_FIGURE_CAPTION]") ->
          {:ok, "\\begin{CAPTION}Distribution of feature_3 values.\\end{CAPTION}"}

        String.contains?(prompt, "[DENARIO_PAPER_REFINE_RESULTS]") ->
          {:ok,
           "\\begin{RESULTS}Results emphasize feature_3 and cite Fig. \\ref{fig:feature_distributions}.\\begin{figure}[t]\\centering\\includegraphics[width=0.48\\textwidth]{feature_distributions.png}\\caption{Distribution of feature_3 values with 95% intervals.}\\label{fig:feature_distributions}\\end{figure}\\end{RESULTS}"}

        true ->
          {:error, {:unexpected_prompt, prompt}}
      end
    end

    @impl true
    def generate_object([%{role: "user", content: prompt}], _schema, _opts) do
      cond do
        String.contains?(prompt, "[DENARIO_PAPER_ABSTRACT]") ->
          {:ok,
           %{
             "title" => "Feature_3 Analysis for Tiny Anomaly Datasets",
             "abstract" => "We analyze feature_3 and report 95% uncertainty intervals."
           }}

        true ->
          {:error, {:unexpected_object_prompt, prompt}}
      end
    end
  end

  defmodule PlotSelectionClient do
    @behaviour DenarioEx.LLMClient

    @impl true
    def complete([%{role: "user", content: prompt}], _opts) do
      cond do
        String.contains?(prompt, "[DENARIO_PAPER_KEYWORDS]") ->
          {:ok, "\\begin{KEYWORDS}plot selection, anomaly detection\\end{KEYWORDS}"}

        String.contains?(prompt, "[DENARIO_PAPER_SECTION][Introduction]") ->
          {:ok, "\\begin{INTRODUCTION}Introduction.\\end{INTRODUCTION}"}

        String.contains?(prompt, "[DENARIO_PAPER_SECTION][Methods]") ->
          {:ok, "\\begin{METHODS}Methods.\\end{METHODS}"}

        String.contains?(prompt, "[DENARIO_PAPER_SECTION][Results]") ->
          {:ok, "\\begin{RESULTS}Results before figures.\\end{RESULTS}"}

        String.contains?(prompt, "[DENARIO_PAPER_SECTION][Conclusions]") ->
          {:ok, "\\begin{CONCLUSIONS}Conclusions.\\end{CONCLUSIONS}"}

        String.contains?(prompt, "[DENARIO_PAPER_FIGURE_CAPTION]") ->
          {:ok, "\\begin{CAPTION}Figure caption.\\end{CAPTION}"}

        String.contains?(prompt, "[DENARIO_PAPER_REFINE_RESULTS]") and
            String.contains?(prompt, "feature_distributions.png") ->
          {:ok,
           "\\begin{RESULTS}\\begin{figure}[t]\\centering\\includegraphics[width=0.48\\textwidth]{feature_distributions.png}\\caption{Figure caption.}\\label{fig:feature-distributions}\\end{figure}\\end{RESULTS}"}

        String.contains?(prompt, "[DENARIO_PAPER_REFINE_RESULTS]") and
            String.contains?(prompt, "stale_plot.png") ->
          {:ok,
           "\\begin{RESULTS}\\begin{figure}[t]\\centering\\includegraphics[width=0.48\\textwidth]{stale_plot.png}\\caption{Figure caption.}\\label{fig:stale-plot}\\end{figure}\\end{RESULTS}"}

        true ->
          {:error, {:unexpected_prompt, prompt}}
      end
    end

    @impl true
    def generate_object([%{role: "user", content: prompt}], _schema, _opts) do
      cond do
        String.contains?(prompt, "[DENARIO_PAPER_ABSTRACT]") ->
          {:ok,
           %{
             "title" => "Plot Selection",
             "abstract" => "Abstract."
           }}

        true ->
          {:error, {:unexpected_object_prompt, prompt}}
      end
    end
  end

  setup do
    project_dir =
      Path.join(
        System.tmp_dir!(),
        "denario_ex_paper_workflow_#{System.unique_integer([:positive])}"
      )

    on_exit(fn -> File.rm_rf(project_dir) end)
    {:ok, project_dir: project_dir}
  end

  test "paper generation escapes latex-special prose while preserving refs and figure paths", %{
    project_dir: project_dir
  } do
    plots_dir = Path.join(project_dir, "input_files/plots")

    assert {:ok, denario} = DenarioEx.new(project_dir: project_dir, clear_project_dir: true)
    assert {:ok, denario} = DenarioEx.set_data_description(denario, "Tiny anomaly dataset.")
    assert {:ok, denario} = DenarioEx.set_idea(denario, "Interpret feature_3 shifts.")

    assert {:ok, denario} =
             DenarioEx.set_method(denario, "Measure feature_3 and summarize 95% intervals.")

    assert {:ok, denario} =
             DenarioEx.set_results(denario, "feature_3 dominates the anomaly score.")

    File.mkdir_p!(plots_dir)
    File.write!(Path.join(plots_dir, "feature_distributions.png"), "fake png bytes")

    assert {:ok, denario} =
             DenarioEx.get_paper(
               denario,
               client: LatexSafeClient,
               llm: "openai:gpt-4.1-mini",
               writer: "scientist",
               journal: :neurips,
               add_citations: false,
               compile: false
             )

    tex = File.read!(denario.research.paper_tex_path)

    assert String.contains?(tex, "\\title{Feature\\_3 Analysis for Tiny Anomaly Datasets}")
    assert String.contains?(tex, "feature\\_3")
    assert String.contains?(tex, "95\\%")
    assert String.contains?(tex, "\\ref{fig:feature_distributions}")
    assert String.contains?(tex, "\\label{fig:feature_distributions}")
    assert String.contains?(tex, "../input_files/plots/feature_distributions.png")
  end

  test "compile: false removes a stale paper PDF instead of leaving old output on disk", %{
    project_dir: project_dir
  } do
    plots_dir = Path.join(project_dir, "input_files/plots")
    stale_pdf_path = Path.join(project_dir, "paper/paper_v4_final.pdf")

    assert {:ok, denario} = DenarioEx.new(project_dir: project_dir, clear_project_dir: true)
    assert {:ok, denario} = DenarioEx.set_data_description(denario, "Tiny anomaly dataset.")
    assert {:ok, denario} = DenarioEx.set_idea(denario, "Interpret feature_3 shifts.")

    assert {:ok, denario} =
             DenarioEx.set_method(denario, "Measure feature_3 and summarize 95% intervals.")

    assert {:ok, denario} =
             DenarioEx.set_results(denario, "feature_3 dominates the anomaly score.")

    File.mkdir_p!(plots_dir)
    File.write!(Path.join(plots_dir, "feature_distributions.png"), "fake png bytes")
    File.mkdir_p!(Path.dirname(stale_pdf_path))
    File.write!(stale_pdf_path, "stale pdf bytes")

    assert {:ok, denario} =
             DenarioEx.get_paper(
               denario,
               client: LatexSafeClient,
               llm: "openai:gpt-4.1-mini",
               writer: "scientist",
               journal: :neurips,
               add_citations: false,
               compile: false
             )

    assert denario.research.paper_pdf_path == nil
    refute File.exists?(stale_pdf_path)
  end

  test "paper generation prefers current project plots over stale in-memory plot paths", %{
    project_dir: project_dir
  } do
    plots_dir = Path.join(project_dir, "input_files/plots")

    assert {:ok, denario} = DenarioEx.new(project_dir: project_dir, clear_project_dir: true)
    assert {:ok, denario} = DenarioEx.set_data_description(denario, "Tiny anomaly dataset.")
    assert {:ok, denario} = DenarioEx.set_idea(denario, "Interpret feature_3 shifts.")
    assert {:ok, denario} = DenarioEx.set_method(denario, "Method.")
    assert {:ok, denario} = DenarioEx.set_results(denario, "Results.")

    File.mkdir_p!(plots_dir)
    File.write!(Path.join(plots_dir, "feature_distributions.png"), "fake png bytes")

    denario = %{denario | research: %{denario.research | plot_paths: ["/tmp/stale_plot.png"]}}

    assert {:ok, denario} =
             DenarioEx.get_paper(
               denario,
               client: PlotSelectionClient,
               llm: "openai:gpt-4.1-mini",
               writer: "scientist",
               journal: :neurips,
               add_citations: false,
               compile: false
             )

    tex = File.read!(denario.research.paper_tex_path)

    assert String.contains?(tex, "../input_files/plots/feature_distributions.png")
    refute String.contains?(tex, "stale_plot.png")
  end
end
