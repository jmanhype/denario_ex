defmodule DenarioEx.CompatibilityTest do
  use ExUnit.Case, async: true

  alias DenarioEx
  alias DenarioEx.ArtifactRegistry

  setup do
    project_dir =
      Path.join(
        System.tmp_dir!(),
        "denario_ex_compat_#{System.unique_integer([:positive])}"
      )

    on_exit(fn -> File.rm_rf(project_dir) end)
    {:ok, project_dir: project_dir}
  end

  test "reset/1 clears in-memory research while leaving persisted artifacts intact", %{
    project_dir: project_dir
  } do
    assert {:ok, denario} = DenarioEx.new(project_dir: project_dir, clear_project_dir: true)
    assert {:ok, denario} = DenarioEx.set_data_description(denario, "Persisted description")
    assert {:ok, denario} = DenarioEx.set_idea(denario, "Persisted idea")

    assert {:ok, reset} = DenarioEx.reset(denario)

    assert reset.research.data_description == ""
    assert reset.research.idea == ""

    assert File.read!(Path.join(project_dir, "input_files/data_description.md")) ==
             "Persisted description"

    assert File.read!(Path.join(project_dir, "input_files/idea.md")) == "Persisted idea"
  end

  test "set_all/1 reloads persisted content into a reset session", %{project_dir: project_dir} do
    assert {:ok, denario} = DenarioEx.new(project_dir: project_dir, clear_project_dir: true)
    assert {:ok, denario} = DenarioEx.set_data_description(denario, "Research description")
    assert {:ok, denario} = DenarioEx.set_idea(denario, "Research idea")
    assert {:ok, denario} = DenarioEx.set_method(denario, "Research method")
    assert {:ok, denario} = DenarioEx.set_results(denario, "Research results")

    plot_path = Path.join(project_dir, "source_plot.png")
    File.write!(plot_path, "fake png bytes")

    assert {:ok, denario} = DenarioEx.set_plots(denario, [plot_path])
    assert {:ok, denario} = DenarioEx.reset(denario)
    assert {:ok, denario} = DenarioEx.set_all(denario)

    assert denario.research.data_description == "Research description"
    assert denario.research.idea == "Research idea"
    assert denario.research.methodology == "Research method"
    assert denario.research.results == "Research results"
    assert Enum.any?(denario.research.plot_paths, &String.ends_with?(&1, "source_plot.png"))
  end

  test "set_all/1 clears stale in-memory artifacts when files were removed from disk", %{
    project_dir: project_dir
  } do
    assert {:ok, denario} = DenarioEx.new(project_dir: project_dir, clear_project_dir: true)
    assert {:ok, denario} = DenarioEx.set_data_description(denario, "Research description")
    assert {:ok, denario} = DenarioEx.set_idea(denario, "Research idea")

    assert :ok =
             ArtifactRegistry.persist_keywords(
               project_dir,
               ["PHYSICS", "Acoustics"],
               kw_type: :unesco
             )

    tex_path = ArtifactRegistry.path(project_dir, :paper_tex)
    pdf_path = ArtifactRegistry.path(project_dir, :paper_pdf)
    File.mkdir_p!(Path.dirname(tex_path))
    File.write!(tex_path, "paper tex")
    File.write!(pdf_path, "paper pdf")

    assert {:ok, denario} = DenarioEx.set_all(denario)
    assert denario.research.keywords == ["PHYSICS", "Acoustics"]
    assert denario.research.paper_tex_path == tex_path
    assert denario.research.paper_pdf_path == pdf_path

    File.rm!(ArtifactRegistry.path(project_dir, :data_description))
    File.rm!(ArtifactRegistry.path(project_dir, :keywords))
    File.rm!(tex_path)
    File.rm!(pdf_path)

    assert {:ok, denario} = DenarioEx.set_all(denario)

    assert denario.research.data_description == ""
    assert denario.research.idea == "Research idea"
    assert denario.research.keywords == %{}
    assert denario.research.paper_tex_path == nil
    assert denario.research.paper_pdf_path == nil
  end

  test "show_keywords/1 formats both map and list keyword shapes", %{project_dir: project_dir} do
    assert {:ok, denario} = DenarioEx.new(project_dir: project_dir, clear_project_dir: true)

    denario = %{
      denario
      | research: %{denario.research | keywords: %{"urban sensing" => "https://example.com"}}
    }

    assert DenarioEx.show_keywords(denario) == "- [urban sensing](https://example.com)"

    denario = %{
      denario
      | research: %{denario.research | keywords: ["anomaly detection", "time-series"]}
    }

    assert DenarioEx.show_keywords(denario) ==
             "- anomaly detection\n- time-series"
  end

  test "research_pilot/3 runs the full offline workflow with nested stage opts", %{
    project_dir: project_dir
  } do
    assert {:ok, denario} = DenarioEx.new(project_dir: project_dir, clear_project_dir: true)

    assert {:ok, denario} =
             DenarioEx.research_pilot(
               denario,
               """
               Analyze a tiny hypothetical urban microclimate dataset collected from dense low-cost sensor nodes.
               Propose one interpretable anomaly-detection direction and write a short paper draft.
               """,
               idea: [
                 client: DenarioEx.OfflineDemo.Client,
                 llm: "openai:gpt-4.1-mini",
                 iterations: 2
               ],
               method: [
                 client: DenarioEx.OfflineDemo.Client,
                 llm: "openai:gpt-4.1-mini"
               ],
               results: [
                 client: DenarioEx.OfflineDemo.Client,
                 executor: DenarioEx.OfflineDemo.Executor,
                 planner_model: "openai:gpt-4.1-mini",
                 plan_reviewer_model: "openai:gpt-4.1-mini",
                 engineer_model: "openai:gpt-4.1-mini",
                 researcher_model: "openai:gpt-4.1-mini",
                 formatter_model: "openai:gpt-4.1-mini",
                 max_n_attempts: 1
               ],
               literature: [
                 client: DenarioEx.OfflineDemo.Client,
                 semantic_scholar_client: DenarioEx.OfflineDemo.LiteratureClient,
                 llm: "openai:gpt-4.1-mini",
                 max_iterations: 3
               ],
               paper: [
                 client: DenarioEx.OfflineDemo.Client,
                 llm: "openai:gpt-4.1-mini",
                 writer: "climate scientist",
                 journal: :neurips,
                 add_citations: true,
                 compile: false
               ]
             )

    assert String.contains?(denario.research.idea, "Interpretable anomaly detection")
    assert String.contains?(denario.research.results, "stable performance")
    assert String.contains?(denario.research.literature, "can be considered novel")
    assert denario.research.paper_tex_path
    assert File.exists?(denario.research.paper_tex_path)
  end
end
