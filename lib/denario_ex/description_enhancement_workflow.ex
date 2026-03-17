defmodule DenarioEx.DescriptionEnhancementWorkflow do
  @moduledoc false

  alias DenarioEx.{AI, LLM, Progress, ReqLLMClient, Text, WorkflowPrompts}

  @spec run(DenarioEx.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def run(session, opts \\ []) do
    client = Keyword.get(opts, :client, ReqLLMClient)

    Progress.emit(opts, %{
      kind: :started,
      message: "Rewriting the data description into a cleaner scientific brief.",
      progress: 10,
      stage: "description:start"
    })

    with {:ok, summarizer_llm} <- LLM.parse(Keyword.get(opts, :summarizer_model, "gpt-4.1-mini")),
         {:ok, formatter_llm} <-
           LLM.parse(Keyword.get(opts, :summarizer_response_formatter_model, summarizer_llm)),
         prompt <-
           WorkflowPrompts.description_enhancement_prompt(session.research.data_description),
         {:ok, draft} <- AI.complete(client, prompt, summarizer_llm, session.keys),
         :ok <-
           Progress.emit(opts, %{
             kind: :progress,
             message: "Draft enhancement complete. Formatting the final description.",
             progress: 60,
             stage: "description:formatting"
           }),
         formatter_prompt <-
           WorkflowPrompts.description_enhancement_format_prompt(
             session.research.data_description,
             draft
           ),
         {:ok, formatted} <- AI.complete(client, formatter_prompt, formatter_llm, session.keys),
         {:ok, enhanced} <- Text.extract_block_or_fallback(formatted, "ENHANCED_DESCRIPTION") do
      Progress.emit(opts, %{
        kind: :finished,
        status: :success,
        message: "Enhanced description ready.",
        progress: 90,
        stage: "description:complete"
      })

      {:ok, enhanced}
    end
  end
end
