defmodule DenarioExUIWeb.DashboardLiveTest do
  use DenarioExUIWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias DenarioEx

  test "root route renders the dashboard shell", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Denario Ex Control Room"
    assert html =~ "Open Or Create Project"
    assert html =~ "Project State"
  end

  test "project_dir query loads persisted project artifacts", %{conn: conn} do
    project_dir =
      Path.join(
        System.tmp_dir!(),
        "denario_ex_ui_live_test_#{System.unique_integer([:positive])}"
      )

    {:ok, denario} = DenarioEx.new(project_dir: project_dir, clear_project_dir: true)
    {:ok, denario} = DenarioEx.set_data_description(denario, "Urban microclimate sensor dataset.")

    {:ok, denario} =
      DenarioEx.set_idea(denario, "Interpret calibration drift while detecting anomalies.")

    {:ok, _denario} =
      DenarioEx.set_method(denario, "Temporal residual scoring with interpretable features.")

    {:ok, _view, html} = live(conn, ~p"/?project_dir=#{project_dir}")

    assert html =~ "Urban microclimate sensor dataset."
    assert html =~ "Interpret calibration drift while detecting anomalies."
    assert html =~ "Temporal residual scoring with interpretable features."
    assert html =~ project_dir
  end
end
