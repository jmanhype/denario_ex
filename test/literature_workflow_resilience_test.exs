defmodule DenarioEx.LiteratureWorkflowResilienceTest do
  use ExUnit.Case, async: true

  alias DenarioEx

  defmodule FakeClient do
    @behaviour DenarioEx.LLMClient

    @impl true
    def complete([%{role: "user", content: prompt}], _opts) do
      if String.contains?(prompt, "[DENARIO_LITERATURE_SUMMARY]") do
        {:ok, "\\begin{SUMMARY}Idea literature search unavailable\\end{SUMMARY}"}
      else
        {:error, {:unexpected_prompt, prompt}}
      end
    end

    @impl true
    def generate_object([%{role: "user", content: prompt}], _schema, _opts) do
      if String.contains?(prompt, "[DENARIO_LITERATURE_DECISION]") do
        {:ok,
         %{
           "reason" => "Search the literature before deciding novelty.",
           "decision" => "query",
           "query" => "synthetic anomaly score analysis"
         }}
      else
        {:error, {:unexpected_object_prompt, prompt}}
      end
    end
  end

  defmodule RateLimitedSemanticScholarClient do
    @behaviour DenarioEx.SemanticScholarClient

    @impl true
    def search(_query, _keys, _opts) do
      {:error, {:semantic_scholar_http_error, 429, %{"message" => "Too Many Requests"}}}
    end
  end

  defmodule FailingFallbackClient do
    @behaviour DenarioEx.SemanticScholarClient

    @impl true
    def search(_query, _keys, _opts) do
      {:error, {:openalex_http_error, 503, %{"message" => "Unavailable"}}}
    end
  end

  defmodule BlankQueryDecisionClient do
    @behaviour DenarioEx.LLMClient

    @impl true
    def complete([%{role: "user", content: prompt}], _opts) do
      if String.contains?(prompt, "[DENARIO_LITERATURE_SUMMARY]") do
        {:ok, "\\begin{SUMMARY}Unexpected summary\\end{SUMMARY}"}
      else
        {:error, {:unexpected_prompt, prompt}}
      end
    end

    @impl true
    def generate_object([%{role: "user", content: prompt}], _schema, _opts) do
      if String.contains?(prompt, "[DENARIO_LITERATURE_DECISION]") do
        {:ok,
         %{
           "reason" => "Another search is needed.",
           "decision" => "query",
           "query" => "   "
         }}
      else
        {:error, {:unexpected_object_prompt, prompt}}
      end
    end
  end

  defmodule UnexpectedSearchClient do
    @behaviour DenarioEx.SemanticScholarClient

    @impl true
    def search(query, _keys, _opts) do
      send(self(), {:unexpected_search, query})
      {:ok, %{"data" => []}}
    end
  end

  defmodule AccumulatingDecisionClient do
    @behaviour DenarioEx.LLMClient

    @impl true
    def complete([%{role: "user", content: prompt}], _opts) do
      if String.contains?(prompt, "[DENARIO_LITERATURE_SUMMARY]") do
        {:ok, "\\begin{SUMMARY}Accumulated literature summary\\end{SUMMARY}"}
      else
        {:error, {:unexpected_prompt, prompt}}
      end
    end

    @impl true
    def generate_object([%{role: "user", content: prompt}], _schema, _opts) do
      cond do
        String.contains?(prompt, "[DENARIO_LITERATURE_DECISION]") and
            String.contains?(prompt, "Round: 0/3") ->
          send(self(), {:literature_decision_prompt, 0, prompt})

          {:ok,
           %{
             "reason" => "Start with a first query.",
             "decision" => "query",
             "query" => "first query"
           }}

        String.contains?(prompt, "[DENARIO_LITERATURE_DECISION]") and
            String.contains?(prompt, "Round: 1/3") ->
          send(self(), {:literature_decision_prompt, 1, prompt})

          {:ok,
           %{
             "reason" => "Search a second angle as well.",
             "decision" => "query",
             "query" => "second query"
           }}

        String.contains?(prompt, "[DENARIO_LITERATURE_DECISION]") and
            String.contains?(prompt, "Round: 2/3") ->
          send(self(), {:literature_decision_prompt, 2, prompt})

          {:ok,
           %{
             "reason" => "The combined evidence is enough.",
             "decision" => "novel",
             "query" => ""
           }}

        String.contains?(prompt, "[DENARIO_LITERATURE_SELECT]") and
            String.contains?(prompt, "first-paper") ->
          {:ok,
           %{
             "selected_paper_ids" => ["first-paper"],
             "rationale" => "Keep the first relevant paper."
           }}

        String.contains?(prompt, "[DENARIO_LITERATURE_SELECT]") and
            String.contains?(prompt, "second-paper") ->
          {:ok,
           %{
             "selected_paper_ids" => ["second-paper"],
             "rationale" => "Keep the second relevant paper."
           }}

        true ->
          {:error, {:unexpected_object_prompt, prompt}}
      end
    end
  end

  defmodule TwoRoundSemanticScholarClient do
    @behaviour DenarioEx.SemanticScholarClient

    @impl true
    def search("first query", _keys, _opts) do
      {:ok,
       %{
         "data" => [
           %{
             "paperId" => "first-paper",
             "title" => "First paper title",
             "year" => 2024,
             "abstract" => "First paper abstract about sensor anomaly detection.",
             "url" => "https://example.com/first",
             "authors" => [%{"name" => "Ada Lovelace"}],
             "citationCount" => 5
           }
         ]
       }}
    end

    def search("second query", _keys, _opts) do
      {:ok,
       %{
         "data" => [
           %{
             "paperId" => "second-paper",
             "title" => "Second paper title",
             "year" => 2025,
             "abstract" => "Second paper abstract about sensor anomaly detection.",
             "url" => "https://example.com/second",
             "authors" => [%{"name" => "Grace Hopper"}],
             "citationCount" => 7
           }
         ]
       }}
    end
  end

  setup do
    project_dir =
      Path.join(
        System.tmp_dir!(),
        "denario_ex_lit_resilience_#{System.unique_integer([:positive])}"
      )

    on_exit(fn -> File.rm_rf(project_dir) end)
    {:ok, project_dir: project_dir}
  end

  test "check_idea degrades cleanly when Semantic Scholar rate limits the request", %{
    project_dir: project_dir
  } do
    assert {:ok, denario} = DenarioEx.new(project_dir: project_dir, clear_project_dir: true)

    assert {:ok, denario} =
             DenarioEx.set_data_description(denario, "Synthetic anomaly-score study.")

    assert {:ok, denario} = DenarioEx.set_idea(denario, "Interpret synthetic anomaly scores.")

    assert {:ok, denario} =
             DenarioEx.check_idea(
               denario,
               client: FakeClient,
               semantic_scholar_client: RateLimitedSemanticScholarClient,
               fallback_literature_client: FailingFallbackClient,
               llm: "openai:gpt-4.1-mini",
               max_iterations: 2
             )

    assert String.contains?(denario.research.literature, "Idea literature search unavailable")
    assert denario.research.literature_sources == []
  end

  test "later literature decision rounds keep earlier selected papers in context", %{
    project_dir: project_dir
  } do
    assert {:ok, denario} = DenarioEx.new(project_dir: project_dir, clear_project_dir: true)

    assert {:ok, denario} =
             DenarioEx.set_data_description(denario, "Synthetic anomaly-score study.")

    assert {:ok, denario} =
             DenarioEx.set_idea(denario, "Interpretable sensor anomaly detection.")

    assert {:ok, denario} =
             DenarioEx.check_idea(
               denario,
               client: AccumulatingDecisionClient,
               semantic_scholar_client: TwoRoundSemanticScholarClient,
               llm: "openai:gpt-4.1-mini",
               max_iterations: 3
             )

    assert_received {:literature_decision_prompt, 2, prompt}
    assert String.contains?(prompt, "First paper title")
    assert String.contains?(prompt, "Second paper title")
    assert length(denario.research.literature_sources) == 2
  end

  test "check_idea rejects empty follow-up literature queries before searching", %{
    project_dir: project_dir
  } do
    assert {:ok, denario} = DenarioEx.new(project_dir: project_dir, clear_project_dir: true)
    assert {:ok, denario} = DenarioEx.set_data_description(denario, "Synthetic anomaly-score study.")
    assert {:ok, denario} = DenarioEx.set_idea(denario, "Interpretable sensor anomaly detection.")

    assert {:error, {:missing_field, :literature_query}} =
             DenarioEx.check_idea(
               denario,
               client: BlankQueryDecisionClient,
               semantic_scholar_client: UnexpectedSearchClient,
               llm: "openai:gpt-4.1-mini",
               max_iterations: 3
             )

    refute_received {:unexpected_search, _query}
  end
end
