defmodule DenarioExUI.ProjectsTest do
  use ExUnit.Case, async: true

  alias DenarioEx
  alias DenarioEx.ArtifactRegistry
  alias DenarioExUI.Projects

  setup do
    project_dir =
      Path.join(
        System.tmp_dir!(),
        "denario_ex_projects_#{System.unique_integer([:positive])}"
      )

    on_exit(fn -> File.rm_rf(project_dir) end)
    {:ok, project_dir: project_dir}
  end

  test "snapshot prefers current project plots on disk over stale in-memory plot paths", %{
    project_dir: project_dir
  } do
    assert {:ok, denario} = DenarioEx.new(project_dir: project_dir, clear_project_dir: true)

    plot_path = Path.join(ArtifactRegistry.plots_dir(project_dir), "diagnostic_plot.png")
    File.write!(plot_path, "fake png bytes")

    denario = %{denario | research: %{denario.research | plot_paths: ["/tmp/stale_plot.png"]}}

    snapshot = Projects.snapshot(denario)

    assert snapshot.plot_paths == [plot_path]
    assert snapshot.available_outputs["plots"]
  end
end
