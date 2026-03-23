defmodule DenarioExTest do
  use ExUnit.Case, async: true

  alias DenarioEx

  defmodule FakeClient do
    @behaviour DenarioEx.LLMClient

    @impl true
    def complete([%{role: "user", content: prompt}], opts) do
      send(self(), {:llm_call, prompt, opts[:model]})

      cond do
        String.contains?(prompt, "Current idea:") ->
          {:ok, "\\begin{CRITIC}Make the idea more concrete and measurable.\\end{CRITIC}"}

        String.contains?(prompt, "Iteration 1") ->
          {:ok,
           "\\begin{IDEA}A concrete sensor robustness study with measurable outcomes.\\end{IDEA}"}

        String.contains?(prompt, "Iteration 0") ->
          {:ok, "\\begin{IDEA}A broad sensor-analysis idea.\\end{IDEA}"}

        String.contains?(prompt, "\\begin{METHODS}") ->
          {:ok,
           "\\begin{METHODS}1. Load the dataset.\\n2. Compare the proposed signals.\\end{METHODS}"}

        true ->
          {:error, {:unexpected_prompt, prompt}}
      end
    end

    @impl true
    def generate_object(_messages, _schema, _opts) do
      {:error, :not_used_in_this_test}
    end
  end

  defmodule RawCriticClient do
    @behaviour DenarioEx.LLMClient

    @impl true
    def complete([%{role: "user", content: prompt}], _opts) do
      cond do
        String.contains?(prompt, "Current idea:") ->
          {:ok, "Make the idea more concrete, measurable, and operationally testable."}

        String.contains?(prompt, "Iteration 1") ->
          {:ok,
           "\\begin{IDEA}A concrete sensor robustness study with measurable outcomes.\\end{IDEA}"}

        String.contains?(prompt, "Iteration 0") ->
          {:ok, "\\begin{IDEA}A broad sensor-analysis idea.\\end{IDEA}"}

        true ->
          {:error, {:unexpected_prompt, prompt}}
      end
    end

    @impl true
    def generate_object(_messages, _schema, _opts) do
      {:error, :not_used_in_this_test}
    end
  end

  defmodule RawMethodsClient do
    @behaviour DenarioEx.LLMClient

    @impl true
    def complete([%{role: "user", content: prompt}], _opts) do
      cond do
        String.contains?(prompt, "Your task is to think about the methods to use in order to carry it out.") ->
          {:ok, "1. Load the dataset. 2. Compare the proposed signals."}

        true ->
          {:error, {:unexpected_prompt, prompt}}
      end
    end

    @impl true
    def generate_object(_messages, _schema, _opts) do
      {:error, :not_used_in_this_test}
    end
  end

  setup do
    project_dir = Path.join(System.tmp_dir!(), "denario_ex_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(project_dir) end)
    {:ok, project_dir: project_dir}
  end

  test "new/1 creates the expected project directories and persists markdown fields", %{
    project_dir: project_dir
  } do
    assert {:ok, denario} = DenarioEx.new(project_dir: project_dir, clear_project_dir: true)

    assert File.dir?(Path.join(project_dir, "input_files"))
    assert File.dir?(Path.join(project_dir, "input_files/plots"))

    assert {:ok, denario} = DenarioEx.set_data_description(denario, "Research description")
    assert {:ok, denario} = DenarioEx.set_idea(denario, "Research idea")
    assert {:ok, denario} = DenarioEx.set_method(denario, "Research method")
    assert {:ok, _denario} = DenarioEx.set_results(denario, "Research results")

    assert File.read!(Path.join(project_dir, "input_files/data_description.md")) ==
             "Research description"

    assert File.read!(Path.join(project_dir, "input_files/idea.md")) == "Research idea"
    assert File.read!(Path.join(project_dir, "input_files/methods.md")) == "Research method"
    assert File.read!(Path.join(project_dir, "input_files/results.md")) == "Research results"

    assert {:ok, reloaded} = DenarioEx.new(project_dir: project_dir)
    assert reloaded.research.data_description == "Research description"
    assert reloaded.research.idea == "Research idea"
    assert reloaded.research.methodology == "Research method"
    assert reloaded.research.results == "Research results"
  end

  test "fast workflows generate idea and methods through a pluggable client", %{
    project_dir: project_dir
  } do
    assert {:ok, denario} = DenarioEx.new(project_dir: project_dir, clear_project_dir: true)

    assert {:ok, denario} =
             DenarioEx.set_data_description(
               denario,
               "Analyze a small hypothetical lab sensor dataset and propose one paper idea."
             )

    assert {:ok, denario} =
             DenarioEx.get_idea_fast(
               denario,
               client: FakeClient,
               llm: "gpt-4.1-mini",
               iterations: 2
             )

    assert denario.research.idea == "A concrete sensor robustness study with measurable outcomes."
    assert File.read!(Path.join(project_dir, "input_files/idea.md")) == denario.research.idea

    assert_received {:llm_call, prompt, "openai:gpt-4.1-mini"}
    assert String.contains?(prompt, "groundbreaking idea")

    assert {:ok, denario} =
             DenarioEx.get_method_fast(
               denario,
               client: FakeClient,
               llm: "gpt-4.1-mini"
             )

    assert String.contains?(denario.research.methodology, "Load the dataset")

    assert File.read!(Path.join(project_dir, "input_files/methods.md")) ==
             denario.research.methodology
  end

  test "get_idea_fast accepts raw critic feedback when block markers are missing", %{
    project_dir: project_dir
  } do
    assert {:ok, denario} = DenarioEx.new(project_dir: project_dir, clear_project_dir: true)

    assert {:ok, denario} =
             DenarioEx.set_data_description(
               denario,
               "Analyze a small hypothetical lab sensor dataset and propose one paper idea."
             )

    assert {:ok, denario} =
             DenarioEx.get_idea_fast(
               denario,
               client: RawCriticClient,
               llm: "gpt-4.1-mini",
               iterations: 2
             )

    assert denario.research.idea == "A concrete sensor robustness study with measurable outcomes."
    assert File.read!(Path.join(project_dir, "input_files/idea.md")) == denario.research.idea
  end

  test "get_method_fast accepts raw methodology text when block markers are missing", %{
    project_dir: project_dir
  } do
    assert {:ok, denario} = DenarioEx.new(project_dir: project_dir, clear_project_dir: true)

    assert {:ok, denario} =
             DenarioEx.set_data_description(
               denario,
               "Analyze a small hypothetical lab sensor dataset and propose one paper idea."
             )

    assert {:ok, denario} =
             DenarioEx.set_idea(denario, "A concrete sensor robustness study with measurable outcomes.")

    assert {:ok, denario} =
             DenarioEx.get_method_fast(
               denario,
               client: RawMethodsClient,
               llm: "gpt-4.1-mini"
             )

    assert denario.research.methodology == "1. Load the dataset. 2. Compare the proposed signals."
    assert File.read!(Path.join(project_dir, "input_files/methods.md")) == denario.research.methodology
  end

  test "set_plots/2 can rescan the project plots directory without copying files onto themselves",
       %{
         project_dir: project_dir
       } do
    assert {:ok, denario} = DenarioEx.new(project_dir: project_dir, clear_project_dir: true)

    plot_path = Path.join(denario.plots_dir, "existing_plot.png")
    File.write!(plot_path, "fake png bytes")

    assert {:ok, denario} = DenarioEx.set_plots(denario)
    assert denario.research.plot_paths == [plot_path]
    assert File.read!(plot_path) == "fake png bytes"
  end

  test "set_plots/2 with an explicit list removes stale persisted plots", %{
    project_dir: project_dir
  } do
    assert {:ok, denario} = DenarioEx.new(project_dir: project_dir, clear_project_dir: true)

    stale_plot_path = Path.join(denario.plots_dir, "stale_plot.png")
    File.write!(stale_plot_path, "stale png bytes")

    replacement_source = Path.join(project_dir, "fresh_plot.png")
    File.write!(replacement_source, "fresh png bytes")

    assert {:ok, denario} = DenarioEx.set_plots(denario, [replacement_source])

    replacement_destination = Path.join(denario.plots_dir, "fresh_plot.png")

    assert denario.research.plot_paths == [replacement_destination]
    assert File.read!(replacement_destination) == "fresh png bytes"
    refute File.exists?(stale_plot_path)
  end

  test "set_all/1 clears artifacts and paper paths that were deleted on disk", %{
    project_dir: project_dir
  } do
    assert {:ok, session} = DenarioEx.new(project_dir: project_dir, clear_project_dir: true)
    assert {:ok, session_with_idea} = DenarioEx.set_idea(session, "Persisted idea")

    assert {:ok, session_with_method} =
             DenarioEx.set_method(session_with_idea, "Persisted method")

    tex_path = Path.join(project_dir, "paper/paper_v4_final.tex")
    pdf_path = Path.join(project_dir, "paper/paper_v4_final.pdf")
    File.mkdir_p!(Path.dirname(tex_path))
    File.write!(tex_path, "paper tex")
    File.write!(pdf_path, "paper pdf")

    assert {:ok, reloaded_from_disk} = DenarioEx.new(project_dir: project_dir)
    assert reloaded_from_disk.research.idea == "Persisted idea"
    assert reloaded_from_disk.research.paper_tex_path == tex_path
    assert reloaded_from_disk.research.paper_pdf_path == pdf_path

    File.rm!(Path.join(project_dir, "input_files/idea.md"))
    File.rm!(tex_path)
    File.rm!(pdf_path)

    assert session_with_method.research.methodology == "Persisted method"

    assert {:ok, reloaded} = DenarioEx.set_all(reloaded_from_disk)
    assert reloaded.research.idea == ""
    assert reloaded.research.paper_tex_path == nil
    assert reloaded.research.paper_pdf_path == nil
    assert reloaded.research.methodology == "Persisted method"
  end
end
