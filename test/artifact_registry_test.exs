defmodule DenarioEx.ArtifactRegistryTest do
  use ExUnit.Case, async: true

  alias DenarioEx.{ArtifactRegistry, Research}

  setup do
    project_dir =
      Path.join(
        System.tmp_dir!(),
        "denario_ex_artifacts_#{System.unique_integer([:positive])}"
      )

    on_exit(fn -> File.rm_rf(project_dir) end)
    {:ok, project_dir: project_dir}
  end

  test "persist_keywords writes a canonical JSON envelope", %{project_dir: project_dir} do
    assert :ok = ArtifactRegistry.ensure_project_dirs(project_dir)

    assert :ok =
             ArtifactRegistry.persist_keywords(project_dir, ["PHYSICS", "Acoustics"],
               kw_type: :unesco
             )

    payload =
      project_dir
      |> ArtifactRegistry.path(:keywords)
      |> File.read!()
      |> Jason.decode!()

    assert payload["version"] == 1
    assert payload["kw_type"] == "unesco"
    assert payload["shape"] == "list"
    assert payload["keywords"] == ["PHYSICS", "Acoustics"]
  end

  test "load_research reloads persisted content including keywords and referee report", %{
    project_dir: project_dir
  } do
    assert :ok = ArtifactRegistry.ensure_project_dirs(project_dir)

    assert :ok =
             ArtifactRegistry.write_text(project_dir, :data_description, "Persisted description")

    assert :ok = ArtifactRegistry.write_text(project_dir, :idea, "Persisted idea")
    assert :ok = ArtifactRegistry.write_text(project_dir, :methodology, "Persisted methods")
    assert :ok = ArtifactRegistry.write_text(project_dir, :results, "Persisted results")
    assert :ok = ArtifactRegistry.write_text(project_dir, :literature, "Persisted literature")

    assert :ok =
             ArtifactRegistry.write_text(project_dir, :referee_report, "Persisted referee report")

    assert :ok =
             ArtifactRegistry.persist_keywords(
               project_dir,
               %{"A stars" => "http://astrothesaurus.org/uat/5"},
               kw_type: :aas
             )

    plot_path = Path.join(ArtifactRegistry.plots_dir(project_dir), "anomaly_scores.png")
    File.write!(plot_path, "fake png bytes")

    tex_path = ArtifactRegistry.path(project_dir, :paper_tex)
    pdf_path = ArtifactRegistry.path(project_dir, :paper_pdf)
    File.mkdir_p!(Path.dirname(tex_path))
    File.write!(tex_path, "paper tex")
    File.write!(pdf_path, "paper pdf")

    research = ArtifactRegistry.load_research(project_dir, %Research{})

    assert research.data_description == "Persisted description"
    assert research.idea == "Persisted idea"
    assert research.methodology == "Persisted methods"
    assert research.results == "Persisted results"
    assert research.literature == "Persisted literature"
    assert research.referee_report == "Persisted referee report"
    assert research.keywords == %{"A stars" => "http://astrothesaurus.org/uat/5"}
    assert research.paper_tex_path == tex_path
    assert research.paper_pdf_path == pdf_path
    assert Enum.any?(research.plot_paths, &String.ends_with?(&1, "anomaly_scores.png"))
  end
end
