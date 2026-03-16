defmodule DenarioEx.DescriptionEnhancementWorkflow do
  @moduledoc false

  alias DenarioEx.{AI, LLM, ReqLLMClient, Text, WorkflowPrompts}

  @spec run(DenarioEx.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def run(session, opts \\ []) do
    client = Keyword.get(opts, :client, ReqLLMClient)

    with {:ok, summarizer_llm} <- LLM.parse(Keyword.get(opts, :summarizer_model, "gpt-4.1-mini")),
         {:ok, formatter_llm} <-
           LLM.parse(Keyword.get(opts, :summarizer_response_formatter_model, summarizer_llm)),
         prompt <-
           WorkflowPrompts.description_enhancement_prompt(session.research.data_description),
         {:ok, draft} <- AI.complete(client, prompt, summarizer_llm, session.keys),
         formatter_prompt <-
           WorkflowPrompts.description_enhancement_format_prompt(
             session.research.data_description,
             draft
           ),
         {:ok, formatted} <- AI.complete(client, formatter_prompt, formatter_llm, session.keys),
         {:ok, enhanced} <- Text.extract_block_or_fallback(formatted, "ENHANCED_DESCRIPTION") do
      {:ok, enhanced}
    end
  end
end
