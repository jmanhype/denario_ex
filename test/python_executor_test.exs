defmodule DenarioEx.PythonExecutorTest do
  use ExUnit.Case, async: true

  alias DenarioEx.PythonExecutor

  setup do
    work_dir =
      Path.join(
        System.tmp_dir!(),
        "denario_ex_python_executor_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(work_dir)
    on_exit(fn -> File.rm_rf(work_dir) end)
    {:ok, work_dir: work_dir}
  end

  test "execute/2 injects a headless matplotlib backend", %{work_dir: work_dir} do
    code = """
    import os
    print(os.environ.get("MPLBACKEND", "missing"))
    """

    assert {:ok, result} = PythonExecutor.execute(code, work_dir: work_dir, step_id: "env")
    assert String.contains?(result["output"], "Agg")
  end

  test "execute/2 returns a timeout error instead of hanging forever", %{work_dir: work_dir} do
    code = """
    import time
    time.sleep(2)
    print("done")
    """

    assert {:error, result} =
             PythonExecutor.execute(code,
               work_dir: work_dir,
               step_id: "timeout",
               timeout_ms: 100
             )

    assert result["status"] == 124
    assert String.contains?(result["output"], "timed out")
  end

  test "execute/2 prefers DENARIO_EX_PYTHON over the system interpreter", %{work_dir: work_dir} do
    wrapper_dir = Path.join(work_dir, "fake_venv/bin")
    wrapper_path = Path.join(wrapper_dir, "python")

    File.mkdir_p!(wrapper_dir)

    File.write!(
      wrapper_path,
      """
      #!/bin/sh
      export DENARIO_EXECUTOR_MARKER=from_override
      exec python3 "$@"
      """
    )

    File.chmod!(wrapper_path, 0o755)

    previous = System.get_env("DENARIO_EX_PYTHON")
    System.put_env("DENARIO_EX_PYTHON", wrapper_path)

    on_exit(fn ->
      if previous do
        System.put_env("DENARIO_EX_PYTHON", previous)
      else
        System.delete_env("DENARIO_EX_PYTHON")
      end
    end)

    code = """
    import os
    print(os.environ.get("DENARIO_EXECUTOR_MARKER", "missing"))
    """

    assert {:ok, result} = PythonExecutor.execute(code, work_dir: work_dir, step_id: "override")
    assert String.contains?(result["output"], "from_override")
  end
end
