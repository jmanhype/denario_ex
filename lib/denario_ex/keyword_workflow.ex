defmodule DenarioEx.KeywordWorkflow do
  @moduledoc false

  alias DenarioEx.{AI, LLM, Progress, ReqLLMClient, WorkflowPrompts}

  @selection_schema %{
    "type" => "object",
    "additionalProperties" => false,
    "properties" => %{
      "selected_keywords" => %{
        "type" => "array",
        "items" => %{"type" => "string"}
      }
    },
    "required" => ["selected_keywords"]
  }

  @assets_dir Path.expand("../../priv/keywords", __DIR__)
  @unesco_level1_limit 3
  @unesco_level2_limit 4
  @unesco_level3_limit 6

  @spec run(DenarioEx.t(), String.t() | nil, keyword()) :: {:ok, map()} | {:error, term()}
  def run(session, input_text, opts \\ []) do
    client = Keyword.get(opts, :client, ReqLLMClient)
    kw_type = normalize_kw_type(Keyword.get(opts, :kw_type, :unesco))
    n_keywords = Keyword.get(opts, :n_keywords, 5)
    text = normalize_input_text(input_text, session.research)

    if text == "" do
      {:error, {:missing_field, :keywords_input}}
    else
      Progress.emit(opts, %{
        kind: :started,
        message: "Selecting #{kw_type} keywords from the current work.",
        progress: 10,
        stage: "keywords:start"
      })

      with {:ok, llm} <- LLM.parse(Keyword.get(opts, :llm, "gpt-4.1-mini")),
           {:ok, keywords} <-
             keywords_for_type(kw_type, text, n_keywords, client, llm, session.keys, opts) do
        Progress.emit(opts, %{
          kind: :finished,
          status: :success,
          message: "Keyword extraction finished.",
          progress: 90,
          stage: "keywords:complete"
        })

        {:ok, %{kw_type: kw_type, keywords: keywords}}
      end
    end
  end

  defp keywords_for_type(:unesco, input_text, n_keywords, client, llm, keys, opts) do
    taxonomy = load_unesco_taxonomy()
    level1_names = Enum.map(taxonomy, &Map.fetch!(&1, "name"))

    Progress.emit(opts, %{
      kind: :progress,
      message: "Scoring UNESCO level 1 domains.",
      progress: 20,
      stage: "keywords:unesco_level1"
    })

    with {:ok, domains} <-
           select_keywords(
             client,
             llm,
             keys,
             "UNESCO",
             "LEVEL1",
             input_text,
             level1_names,
             @unesco_level1_limit,
             opts
           ) do
      domains = maybe_include_mathematics(domains, level1_names)

      Progress.emit(opts, %{
        kind: :progress,
        message: "Narrowing UNESCO level 2 fields.",
        progress: 40,
        stage: "keywords:unesco_level2"
      })

      sub_fields =
        Enum.flat_map(domains, fn domain ->
          candidates =
            taxonomy
            |> Enum.find(&(Map.get(&1, "name") == domain))
            |> case do
              nil ->
                []

              match ->
                match
                |> Map.get("sub_fields", %{})
                |> Map.values()
                |> Enum.map(&Map.fetch!(&1, "name"))
            end

          scoped_input = "Parent keyword: #{domain}\n\n#{input_text}"

          case select_keywords(
                 client,
                 llm,
                 keys,
                 "UNESCO",
                 "LEVEL2",
                 scoped_input,
                 candidates,
                 @unesco_level2_limit,
                 opts
               ) do
            {:ok, values} -> values
            _ -> []
          end
        end)

      Progress.emit(opts, %{
        kind: :progress,
        message: "Selecting UNESCO specific areas.",
        progress: 60,
        stage: "keywords:unesco_level3"
      })

      specific_areas =
        Enum.flat_map(sub_fields, fn sub_field ->
          candidates =
            taxonomy
            |> Enum.flat_map(fn domain ->
              domain
              |> Map.get("sub_fields", %{})
              |> Map.values()
            end)
            |> Enum.find(&(Map.get(&1, "name") == sub_field))
            |> case do
              nil ->
                []

              match ->
                match
                |> Map.get("specific_areas", %{})
                |> Map.values()
                |> Enum.map(&Map.fetch!(&1, "name"))
            end

          scoped_input = "Parent keyword: #{sub_field}\n\n#{input_text}"

          case select_keywords(
                 client,
                 llm,
                 keys,
                 "UNESCO",
                 "LEVEL3",
                 scoped_input,
                 candidates,
                 @unesco_level3_limit,
                 opts
               ) do
            {:ok, values} -> values
            _ -> []
          end
        end)

      aggregate =
        domains
        |> Kernel.++(sub_fields)
        |> Kernel.++(specific_areas)
        |> unique_preserving_order()

      Progress.emit(opts, %{
        kind: :progress,
        message: "Choosing the final UNESCO keyword set.",
        progress: 80,
        stage: "keywords:unesco_final"
      })

      select_keywords(
        client,
        llm,
        keys,
        "UNESCO",
        "FINAL",
        input_text,
        aggregate,
        n_keywords,
        opts
      )
    end
  end

  defp keywords_for_type(:aas, input_text, n_keywords, client, llm, keys, opts) do
    aas_mapping = load_aas_mapping()
    candidates = Map.keys(aas_mapping)

    Progress.emit(opts, %{
      kind: :progress,
      message: "Selecting AAS taxonomy terms.",
      progress: 55,
      stage: "keywords:aas"
    })

    with {:ok, selected} <-
           select_keywords(
             client,
             llm,
             keys,
             "AAS",
             "FINAL",
             input_text,
             candidates,
             n_keywords,
             opts
           ) do
      keywords =
        selected
        |> Enum.map(fn keyword -> {keyword, Map.get(aas_mapping, keyword, "")} end)
        |> Enum.reject(fn {_keyword, url} -> url in [nil, ""] end)
        |> Enum.into(%{})

      {:ok, keywords}
    end
  end

  defp keywords_for_type(:aaai, input_text, n_keywords, client, llm, keys, opts) do
    candidates = load_aaai_keywords()

    Progress.emit(opts, %{
      kind: :progress,
      message: "Selecting AAAI taxonomy terms.",
      progress: 55,
      stage: "keywords:aaai"
    })

    select_keywords(client, llm, keys, "AAAI", "FINAL", input_text, candidates, n_keywords, opts)
  end

  defp select_keywords(
         _client,
         _llm,
         _keys,
         _family,
         _stage,
         _input_text,
         [],
         _n_keywords,
         _opts
       ),
       do: {:ok, []}

  defp select_keywords(client, llm, keys, family, stage, input_text, candidates, n_keywords, opts) do
    Progress.emit(opts, %{
      kind: :progress,
      message: "Scoring #{family} #{stage} candidates.",
      progress: stage_progress(stage),
      stage: "keywords:#{String.downcase(stage)}"
    })

    prompt =
      WorkflowPrompts.keyword_selection_prompt(
        family,
        stage,
        input_text,
        Enum.join(candidates, "\n"),
        n_keywords
      )

    with {:ok, object} <- AI.generate_object(client, prompt, @selection_schema, llm, keys) do
      selected =
        object
        |> Map.get("selected_keywords", [])
        |> Enum.filter(&(&1 in candidates))
        |> Enum.take(n_keywords)

      {:ok, unique_preserving_order(selected)}
    end
  end

  defp normalize_input_text(nil, research) do
    [research.idea, research.methodology, research.results]
    |> Enum.map(&String.trim(to_string(&1 || "")))
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  defp normalize_input_text(text, _research) when is_binary(text), do: String.trim(text)

  defp normalize_kw_type(kw_type) when kw_type in [:unesco, "unesco"], do: :unesco
  defp normalize_kw_type(kw_type) when kw_type in [:aas, "aas"], do: :aas
  defp normalize_kw_type(kw_type) when kw_type in [:aaai, "aaai"], do: :aaai
  defp normalize_kw_type(_kw_type), do: :unesco

  defp load_unesco_taxonomy do
    @assets_dir
    |> Path.join("unesco_hierarchical.json")
    |> File.read!()
    |> Jason.decode!()
    |> Map.values()
  end

  defp load_aas_mapping do
    @assets_dir
    |> Path.join("aas_kwd_to_url.json")
    |> File.read!()
    |> Jason.decode!()
  end

  defp load_aaai_keywords do
    @assets_dir
    |> Path.join("aaai.md")
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(String.starts_with?(&1, "#") or &1 == ""))
  end

  defp maybe_include_mathematics(domains, level1_names) do
    if "MATHEMATICS" in level1_names and "MATHEMATICS" not in domains do
      domains ++ ["MATHEMATICS"]
    else
      domains
    end
  end

  defp unique_preserving_order(values) do
    {_, ordered} =
      Enum.reduce(values, {MapSet.new(), []}, fn value, {seen, acc} ->
        if value in ["", nil] or MapSet.member?(seen, value) do
          {seen, acc}
        else
          {MapSet.put(seen, value), acc ++ [value]}
        end
      end)

    ordered
  end

  defp stage_progress("LEVEL1"), do: 20
  defp stage_progress("LEVEL2"), do: 40
  defp stage_progress("LEVEL3"), do: 60
  defp stage_progress("FINAL"), do: 80
  defp stage_progress(_stage), do: 55
end
