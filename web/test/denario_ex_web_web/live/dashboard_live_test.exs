defmodule DenarioExUIWeb.DashboardLiveTest do
  use DenarioExUIWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias DenarioEx
  alias DenarioEx.ArtifactRegistry
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

  test "blank projects recommend editing the data description instead of a blocked phase", %{
    conn: conn
  } do
    project_dir = tmp_project_dir("blank_project")
    {:ok, _denario} = DenarioEx.new(project_dir: project_dir, clear_project_dir: true)

    {:ok, view, html} = live(conn, ~p"/?project_dir=#{project_dir}")

    assert html =~ "Fill In Data Description"

    assert has_element?(
             view,
             ~s(button[phx-click="select_artifact"][phx-value-artifact="data_description"])
           )
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

  test "research_pilot subphase events disable the matching phase button", %{conn: conn} do
    project_dir = tmp_project_dir("research_pilot_subphase")
    {:ok, denario} = DenarioEx.new(project_dir: project_dir, clear_project_dir: true)
    {:ok, denario} = DenarioEx.set_data_description(denario, "Mesoscale atmospheric dataset.")

    {:ok, _denario} =
      DenarioEx.set_idea(denario, "Detect thermal drift before subsystem failure.")

    {:ok, view, _html} = live(conn, ~p"/?project_dir=#{project_dir}")

    send(
      view.pid,
      {:phase_event,
       %{
         run_id: "run-pilot",
         phase: "research_pilot",
         status: :running,
         kind: :progress,
         progress: 18,
         message: "Generating the research idea.",
         metadata: %{subphase: "get_idea"},
         at: "2026-03-22 10:00:00"
       }}
    )

    assert has_element?(view, ~s(button[phx-value-phase="get_idea"][disabled]))
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

  test "stale output paths do not render broken artifact links", %{conn: conn} do
    project_dir = tmp_project_dir("stale_outputs")
    {:ok, denario} = DenarioEx.new(project_dir: project_dir, clear_project_dir: true)
    {:ok, denario} = DenarioEx.set_data_description(denario, "Satellite telemetry archive.")
    {:ok, view, _html} = live(conn, ~p"/?project_dir=#{project_dir}")

    snapshot =
      denario
      |> Projects.snapshot()
      |> Map.put(:paper_tex_path, "/tmp/missing-paper.tex")
      |> Map.put(:paper_pdf_path, "/tmp/missing-paper.pdf")
      |> Map.put(:referee_log_path, "/tmp/missing-referee.log")
      |> put_in([:available_outputs, "paper_tex"], false)
      |> put_in([:available_outputs, "paper_pdf"], false)
      |> put_in([:available_outputs, "referee_log"], false)

    send(
      view.pid,
      {:phase_event,
       %{
         run_id: "run-stale",
         phase: "get_paper",
         status: :success,
         kind: :finished,
         progress: 100,
         message: "Paper generated.",
         at: "2026-03-22 10:05:00",
         snapshot: snapshot
       }}
    )

    html = render(view)

    refute html =~ "Open TeX"
    refute html =~ "Open PDF"
    refute html =~ "Open Referee Log"
  end

  test "recommended next step stays on paper generation when only plots exist", %{conn: conn} do
    project_dir = tmp_project_dir("next_action_paper")
    {:ok, denario} = DenarioEx.new(project_dir: project_dir, clear_project_dir: true)
    {:ok, denario} = DenarioEx.set_data_description(denario, "Satellite telemetry archive.")
    {:ok, denario} = DenarioEx.set_idea(denario, "Detect thermal drift before subsystem failure.")

    {:ok, denario} =
      DenarioEx.set_method(
        denario,
        "Compare blocked temporal splits with interpretable features."
      )

    {:ok, denario} =
      DenarioEx.set_results(denario, "The detector separates nominal and anomalous periods.")

    plot_path = Path.join(project_dir, "source_plot.png")
    File.write!(plot_path, "fake png bytes")
    {:ok, _denario} = DenarioEx.set_plots(denario, [plot_path])
    :ok = ArtifactRegistry.persist_keywords(project_dir, ["telemetry anomaly detection"])

    {:ok, view, html} = live(conn, ~p"/?project_dir=#{project_dir}")

    assert html =~ "Generate Paper"
    assert has_element?(view, ~s(button[phx-value-phase="get_paper"]))
  end

  test "non-inline plot artifacts render as links without broken image tags", %{conn: conn} do
    project_dir = tmp_project_dir("plot_pdf")
    {:ok, denario} = DenarioEx.new(project_dir: project_dir, clear_project_dir: true)
    {:ok, denario} = DenarioEx.set_data_description(denario, "Satellite telemetry archive.")
    {:ok, view, _html} = live(conn, ~p"/?project_dir=#{project_dir}")

    snapshot =
      denario
      |> Projects.snapshot()
      |> Map.put(:plot_paths, ["/tmp/diagnostic_plot.pdf"])
      |> put_in([:available_outputs, "plots"], true)

    send(
      view.pid,
      {:phase_event,
       %{
         run_id: "run-plot-pdf",
         phase: "get_results",
         status: :success,
         kind: :finished,
         progress: 100,
         message: "Results generated.",
         at: "2026-03-22 10:10:00",
         snapshot: snapshot
       }}
    )

    html = render(view)

    assert html =~ "diagnostic_plot.pdf"
    assert html =~ "Open file"
    refute html =~ ~s(alt="diagnostic_plot.pdf")
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
