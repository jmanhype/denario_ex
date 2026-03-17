defmodule DenarioExUIWeb.DashboardLiveTest do
  use DenarioExUIWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias DenarioEx
  alias DenarioExUI.Projects

  test "root route renders the dashboard shell", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "A research cockpit that tells you what to do next."
    assert html =~ "Open Or Create Project"
    assert html =~ "Workflow Rail"
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

    {:ok, view, html} = live(conn, ~p"/?project_dir=#{project_dir}")

    assert html =~ project_dir
    assert html =~ "Generate Results"

    html =
      view
      |> element(~s(button[phx-value-artifact="idea"]))
      |> render_click()

    assert html =~ "Interpret calibration drift while detecting anomalies."

    html =
      view
      |> element(~s(button[phx-value-artifact="methodology"]))
      |> render_click()

    assert html =~ "Temporal residual scoring with interpretable features."
  end

  test "phase events update the run monitor and live log", %{conn: conn} do
    project_dir = tmp_project_dir("run_monitor")
    {:ok, denario} = DenarioEx.new(project_dir: project_dir, clear_project_dir: true)
    {:ok, _denario} = DenarioEx.set_data_description(denario, "Mesoscale atmospheric dataset.")

    {:ok, view, _html} = live(conn, ~p"/?project_dir=#{project_dir}")

    send(
      view.pid,
      {:phase_event, running_event("run-1", "get_results", 12, "Planning execution run.")}
    )

    send(
      view.pid,
      {:phase_event, running_event("run-1", "get_results", 67, "Step 2 of 4 finished.")}
    )

    html = render(view)

    assert html =~ "Run Monitor"
    assert html =~ "Generate Results"
    assert html =~ "67%"
    assert html =~ "Planning execution run."
    assert html =~ "Step 2 of 4 finished."
    assert html =~ "Cancel Run"
  end

  test "success phase events refresh the loaded project snapshot", %{conn: conn} do
    project_dir = tmp_project_dir("snapshot_refresh")
    {:ok, denario} = DenarioEx.new(project_dir: project_dir, clear_project_dir: true)
    {:ok, denario} = DenarioEx.set_data_description(denario, "Satellite telemetry archive.")
    {:ok, view, _html} = live(conn, ~p"/?project_dir=#{project_dir}")

    {:ok, updated} = DenarioEx.set_idea(denario, "Detect thermal drift before subsystem failure.")
    snapshot = Projects.snapshot(updated)

    send(
      view.pid,
      {:phase_event,
       %{
         run_id: "run-2",
         phase: "get_idea",
         status: :success,
         kind: :finished,
         progress: 100,
         message: "Idea generated.",
         at: "2026-03-16 12:00:00",
         snapshot: snapshot
       }}
    )

    html = render(view)

    assert html =~ "Idea generated."
    assert html =~ "100%"
    assert html =~ "Retry Run"

    html =
      view
      |> element(~s(button[phx-value-artifact="idea"]))
      |> render_click()

    assert html =~ "Detect thermal drift before subsystem failure."
  end

  test "cancelled runs show retry controls and preserve the cancellation state", %{conn: conn} do
    project_dir = tmp_project_dir("cancelled_run")
    {:ok, denario} = DenarioEx.new(project_dir: project_dir, clear_project_dir: true)
    {:ok, _denario} = DenarioEx.set_data_description(denario, "Atmospheric pressure dataset.")

    {:ok, view, _html} = live(conn, ~p"/?project_dir=#{project_dir}")

    send(
      view.pid,
      {:phase_event,
       %{
         run_id: "run-cancelled",
         phase: "get_idea",
         status: :cancelled,
         kind: :finished,
         progress: 100,
         message: "Generate Idea cancelled.",
         at: "2026-03-16 12:30:00"
       }}
    )

    send(view.pid, {:phase_event, running_event("run-cancelled", "get_idea", 80, "late event")})

    html = render(view)

    assert html =~ "Generate Idea cancelled."
    assert html =~ "Retry Run"
    refute html =~ "late event"
  end

  test "intermediate success events do not complete the run before the canonical terminal event",
       %{
         conn: conn
       } do
    project_dir = tmp_project_dir("intermediate_success")
    {:ok, denario} = DenarioEx.new(project_dir: project_dir, clear_project_dir: true)
    {:ok, _denario} = DenarioEx.set_data_description(denario, "Atmospheric temperature dataset.")

    {:ok, view, _html} = live(conn, ~p"/?project_dir=#{project_dir}")

    send(
      view.pid,
      {:phase_event, running_event("run-3", "get_idea", 20, "Generating idea iterations.")}
    )

    send(
      view.pid,
      {:phase_event,
       %{
         run_id: "run-3",
         phase: "get_idea",
         status: :success,
         kind: :finished,
         progress: 95,
         message: "Idea draft written to disk.",
         stage: "idea:complete",
         at: "2026-03-16 13:00:00"
       }}
    )

    html = render(view)

    assert html =~ "Generating idea iterations."
    assert html =~ "Cancel Run"
    refute html =~ "Retry Run"

    send(
      view.pid,
      {:phase_event,
       %{
         run_id: "run-3",
         phase: "get_idea",
         status: :success,
         kind: :finished,
         progress: 100,
         message: "Idea generated.",
         stage: "get_idea:complete",
         at: "2026-03-16 13:00:05"
       }}
    )

    html = render(view)

    assert html =~ "Idea generated."
    assert html =~ "Retry Run"
  end

  defp running_event(run_id, phase, progress, message) do
    %{
      run_id: run_id,
      phase: phase,
      status: :running,
      kind: :progress,
      progress: progress,
      message: message,
      at: "2026-03-16 11:00:00"
    }
  end

  defp tmp_project_dir(prefix) do
    Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}")
  end
end
