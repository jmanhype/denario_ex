defmodule DenarioEx.ProgressTest do
  use ExUnit.Case, async: true

  alias DenarioEx.Progress

  test "emit/2 swallows exiting callbacks instead of crashing the workflow" do
    assert :ok =
             Progress.emit(
               fn _event ->
                 exit(:boom)
               end,
               %{message: "hello"}
             )
  end

  test "emit/2 swallows thrown callbacks instead of crashing the workflow" do
    assert :ok =
             Progress.emit(
               fn _event ->
                 throw(:boom)
               end,
               %{message: "hello"}
             )
  end
end
