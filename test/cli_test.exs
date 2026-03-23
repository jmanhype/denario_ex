defmodule DenarioEx.CLITest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  test "run/1 prints help with no arguments" do
    output =
      capture_io(fn ->
        assert DenarioEx.CLI.run([]) == 0
      end)

    assert String.contains?(output, "denario_ex research-pilot")
    assert String.contains?(output, "denario_ex offline-demo")
  end

  test "offline-demo command writes project artifacts" do
    project_dir =
      Path.join(System.tmp_dir!(), "denario_ex_cli_#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf(project_dir) end)

    output =
      capture_io(fn ->
        assert DenarioEx.CLI.run(["offline-demo", "--project-dir", project_dir]) == 0
      end)

    assert String.contains?(output, "Offline demo completed.")
    assert File.exists?(Path.join(project_dir, "input_files/idea.md"))
    assert File.exists?(Path.join(project_dir, "paper/paper_v4_final.tex"))
  end

  test "research-pilot reports invalid modes instead of crashing" do
    output =
      capture_io(:stderr, fn ->
        assert DenarioEx.CLI.run(["research-pilot", "--mode", "bogus"]) == 1
      end)

    assert output =~ "Unsupported mode"
  end

  test "research-pilot reports missing data descriptions instead of crashing" do
    project_dir =
      Path.join(
        System.tmp_dir!(),
        "denario_ex_cli_missing_description_#{System.unique_integer([:positive])}"
      )

    on_exit(fn -> File.rm_rf(project_dir) end)

    output =
      capture_io(:stderr, fn ->
        assert DenarioEx.CLI.run(["research-pilot", "--project-dir", project_dir]) == 1
      end)

    assert output =~ "Missing required field: data_description"
  end
end
