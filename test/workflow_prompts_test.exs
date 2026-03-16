defmodule DenarioEx.WorkflowPromptsTest do
  use ExUnit.Case, async: true

  alias DenarioEx.WorkflowPrompts

  test "results_engineer_prompt enforces bounded runtime and non-interactive plotting" do
    step = %{
      "id" => "results_1",
      "goal" => "Run the core analysis",
      "deliverable" => "Console output and one plot"
    }

    context = %{
      data_description: "Tiny anomaly-score dataset.",
      idea: "Interpretable anomaly detection.",
      methodology: "Train a lightweight baseline and report one figure."
    }

    prompt = WorkflowPrompts.results_engineer_prompt(step, context, [], "", "")

    assert String.contains?(prompt, "Must finish in under 20 seconds on a single CPU core.")

    assert String.contains?(
             prompt,
             "Do not use heavyweight probabilistic or deep-learning stacks"
           )

    assert String.contains?(prompt, "Never call plt.show().")
    assert String.contains?(prompt, "Save plots as PNG files in the current working directory")
    assert String.contains?(prompt, "Produce at most one PNG figure")
  end

  test "results_engineer_prompt preserves caller-provided hardware constraints" do
    step = %{
      "id" => "results_1",
      "goal" => "Run the core analysis",
      "deliverable" => "Console output and one plot"
    }

    context = %{
      data_description: "Tiny anomaly-score dataset.",
      idea: "Interpretable anomaly detection.",
      methodology: "Train a lightweight baseline and report one figure."
    }

    prompt =
      WorkflowPrompts.results_engineer_prompt(
        step,
        context,
        [],
        "Python execution timed out after 60000 ms",
        "No GPU. Prefer vectorized NumPy over loops."
      )

    assert String.contains?(
             prompt,
             "Previous execution error: Python execution timed out after 60000 ms"
           )

    assert String.contains?(prompt, "No GPU. Prefer vectorized NumPy over loops.")
  end
end
