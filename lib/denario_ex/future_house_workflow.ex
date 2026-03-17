defmodule DenarioEx.FutureHouseWorkflow do
  @moduledoc false

  alias DenarioEx.{FutureHouse, KeyManager, Progress, WorkflowPrompts}

  @spec run(DenarioEx.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(session, opts \\ []) do
    client = Keyword.get(opts, :future_house_client, FutureHouse)

    Progress.emit(opts, %{
      kind: :started,
      message: "Submitting the idea to FutureHouse / Edison.",
      progress: 10,
      stage: "futurehouse:start"
    })

    with %KeyManager{future_house: api_key} when is_binary(api_key) and api_key != "" <-
           session.keys,
         prompt <- WorkflowPrompts.futurehouse_prompt(session.research.idea),
         {:ok, response} <- client.run_owl_review(prompt, session.keys, opts) do
      Progress.emit(opts, %{
        kind: :finished,
        status: :success,
        message: "FutureHouse precedent search finished.",
        progress: 90,
        stage: "futurehouse:complete"
      })

      {:ok,
       %{
         literature: normalize_literature(fetch_formatted_answer(response)),
         sources: [],
         response: response
       }}
    else
      %KeyManager{} -> {:error, {:missing_api_key, :future_house}}
      {:error, _reason} = error -> error
    end
  end

  defp fetch_formatted_answer(response) do
    direct =
      fetch(response, "formatted_answer") ||
        fetch(response, "answer")

    if is_binary(direct) and direct != "" do
      direct
    else
      response
      |> fetch("environment_frame")
      |> fetch("state")
      |> fetch("state")
      |> fetch("response")
      |> fetch("answer")
      |> fetch("formatted_answer")
      |> case do
        answer when is_binary(answer) -> answer
        _ -> ""
      end
    end
  end

  defp normalize_literature(answer) do
    trimmed = String.trim(answer || "")

    cleaned =
      cond do
        trimmed == "" ->
          "Has anyone worked on or explored the following idea?\nNo FutureHouse response was returned."

        String.contains?(trimmed, "</DESIRED_RESPONSE_FORMAT>") ->
          case String.split(trimmed, "</DESIRED_RESPONSE_FORMAT>", parts: 2) do
            [_head, tail] ->
              if byte_size(String.trim(tail)) > 0 do
                String.trim(tail)
              else
                [head, _tail] = String.split(trimmed, "</DESIRED_RESPONSE_FORMAT>", parts: 2)

                head
                |> String.replace("<DESIRED_RESPONSE_FORMAT>", "")
                |> String.trim()
              end
          end

        true ->
          trimmed
      end

    "Has anyone worked on or explored the following idea?\n" <> cleaned
  end

  defp fetch(nil, _key), do: nil

  defp fetch(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, String.to_atom(key))
  end
end
