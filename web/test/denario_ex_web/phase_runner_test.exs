defmodule DenarioExUI.PhaseRunnerTest do
  use ExUnit.Case, async: false

  alias DenarioExUI.{PhaseEvents, PhaseRunner, PhaseRuns}

  test "cancel stops an active run and broadcasts a cancelled event" do
    project_dir =
      Path.join(
        System.tmp_dir!(),
        "denario_ex_phase_runner_#{System.unique_integer([:positive])}"
      )

    run_id = "run-cancel-test"

    :ok = PhaseEvents.subscribe(project_dir)

    pid =
      spawn(fn ->
        Process.sleep(:infinity)
      end)

    PhaseRuns.put(run_id, %{pid: pid, project_dir: project_dir, phase: "get_idea", settings: %{}})

    assert :ok = PhaseRunner.cancel(run_id)

    assert_receive {:phase_event,
                    %{
                      run_id: ^run_id,
                      phase: "get_idea",
                      status: :cancelled,
                      message: "Generate Idea cancelled."
                    }}

    refute Process.alive?(pid)
    assert PhaseRuns.get(run_id) == nil
  end
end
