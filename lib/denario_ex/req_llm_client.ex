defmodule DenarioEx.ReqLLMClient do
  @moduledoc """
  ReqLLM-backed client adapter for Denario text generation.
  """

  @behaviour DenarioEx.LLMClient

  alias ReqLLM.Response
  alias ReqLLM.ToolCall

  @impl true
  def complete(messages, opts) do
    model = Keyword.get(opts, :model_metadata, Keyword.fetch!(opts, :model))

    case ReqLLM.generate_text(model, messages, build_generation_opts(opts)) do
      {:ok, response} ->
        case Response.text(response) do
          text when is_binary(text) and text != "" -> {:ok, text}
          _ -> {:error, {:empty_response, response}}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  @impl true
  def generate_object(messages, schema, opts) do
    model = Keyword.get(opts, :model_metadata, Keyword.fetch!(opts, :model))

    # First try structured output via tool use
    case ReqLLM.generate_object(model, messages, schema, build_generation_opts(opts)) do
      {:ok, response} ->
        case extract_object_from_response(response) do
          {:ok, object} when is_map(object) ->
            {:ok, object}

          {:ok, _other} ->
            {:error, {:non_map_object_response, response}}

          {:error, _error} ->
            # Fallback: re-prompt asking for JSON explicitly via text completion
            json_fallback(model, messages, schema, opts)
        end

      {:error, _error} ->
        json_fallback(model, messages, schema, opts)
    end
  end

  defp json_fallback(model, messages, schema, opts) do
    schema_json = Jason.encode!(schema, pretty: true)

    json_instruction = """

    IMPORTANT: You MUST respond with ONLY a valid JSON object matching this exact schema (no markdown, no explanation, no code fences):
    #{schema_json}
    """

    augmented_messages =
      case List.last(messages) do
        %{role: "user", content: content} ->
          List.replace_at(messages, -1, %{role: "user", content: content <> json_instruction})

        _ ->
          messages ++ [%{role: "user", content: json_instruction}]
      end

    case ReqLLM.generate_text(model, augmented_messages, build_generation_opts(opts)) do
      {:ok, response} ->
        case Response.text(response) do
          text when is_binary(text) and text != "" ->
            case extract_json_from_text(text) do
              {:ok, object} when is_map(object) ->
                {:ok, object}

              _ ->
                # Last resort: try to build object from text patterns
                # (handles engineer responses where code is too large for JSON)
                extract_object_from_text_patterns(text, schema)
            end

          _ ->
            {:error, :empty_fallback_response}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp extract_object_from_text_patterns(text, schema) do
    required = Map.get(schema, "required", [])
    properties = Map.get(schema, "properties", %{})

    # Try to extract each required field from the text
    object =
      Enum.reduce(properties, %{}, fn {key, _spec}, acc ->
        value = extract_field_from_text(text, key)
        if value, do: Map.put(acc, key, value), else: acc
      end)

    if Enum.all?(required, &Map.has_key?(object, &1)) do
      {:ok, object}
    else
      {:error, {:json_fallback_failed, String.slice(text, 0, 500)}}
    end
  end

  defp extract_field_from_text(text, "code") do
    # Extract code from ```python blocks or ```blocks
    case Regex.run(~r/```(?:python)?\s*\n([\s\S]*?)```/s, text) do
      [_, code] -> String.trim(code)
      _ -> nil
    end
  end

  defp extract_field_from_text(text, field) do
    # Try to find "field": "value" or **field:** value patterns
    patterns = [
      ~r/"#{Regex.escape(field)}"\s*:\s*"([^"]*(?:\\.[^"]*)*)"/s,
      ~r/\*\*#{Regex.escape(field)}\*\*[:\s]+(.+?)(?:\n\n|\n\*\*|$)/s,
      ~r/#{Regex.escape(field)}[:\s]+(.+?)(?:\n\n|\n#{Regex.escape(field)}|$)/si
    ]

    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, text) do
        [_, value] -> String.trim(value)
        _ -> nil
      end
    end)
  end

  @doc false
  def build_generation_opts(opts) do
    output_key = if openai_model?(opts), do: :max_completion_tokens, else: :max_tokens

    opts
    |> Keyword.take([:api_key, :temperature, :provider_options])
    |> Keyword.put(output_key, Keyword.fetch!(opts, :max_output_tokens))
    |> maybe_put_openai_json_schema(opts)
  end

  @doc false
  def extract_object_from_response(response) do
    case Response.unwrap_object(response) do
      {:ok, object} ->
        {:ok, object}

      {:error, _reason} ->
        tool_result =
          response
          |> Response.tool_calls()
          |> Enum.find_value(fn
            %ToolCall{} = tool_call ->
              case ToolCall.to_map(tool_call) do
                %{name: "structured_output", arguments: arguments} when is_map(arguments) ->
                  {:ok, arguments}

                _other ->
                  nil
              end

            %{name: "structured_output", arguments: arguments} when is_map(arguments) ->
              {:ok, arguments}

            %{"name" => "structured_output", "arguments" => arguments} when is_map(arguments) ->
              {:ok, arguments}

            _other ->
              nil
          end)

        case tool_result do
          {:ok, _} = result ->
            result

          nil ->
            # Fallback: extract JSON from text response (for providers that
            # return structured data as text instead of tool calls, e.g. Z.ai)
            case Response.text(response) do
              text when is_binary(text) and text != "" ->
                extract_json_from_text(text)

              _ ->
                {:error, :no_structured_output_tool_call}
            end
        end
    end
  end

  defp extract_json_from_text(text) do
    # Strip markdown code fences, thinking tags, and other wrapper noise
    cleaned =
      text
      |> String.replace(~r/```json\s*/s, "")
      |> String.replace(~r/```\s*/s, "")
      |> String.replace(~r/<\/?think>/s, "")
      |> String.trim()

    # Find balanced JSON: walk from first { tracking depth (respecting strings)
    case find_balanced_json(cleaned) do
      {:ok, json_str} ->
        case Jason.decode(json_str) do
          {:ok, object} when is_map(object) -> {:ok, object}
          _ -> {:error, :json_parse_failed}
        end

      :error ->
        {:error, :no_json_in_text}
    end
  end

  defp find_balanced_json(text) do
    graphemes = String.graphemes(text)

    case Enum.find_index(graphemes, &(&1 == "{")) do
      nil ->
        :error

      start_idx ->
        rest = Enum.drop(graphemes, start_idx)
        case walk_json(rest, 0, false, false, []) do
          {:ok, chars} -> {:ok, Enum.join(chars)}
          :error -> :error
        end
    end
  end

  defp walk_json([], _depth, _in_str, _esc, _acc), do: :error

  defp walk_json([char | rest], depth, in_str, escaped, acc) do
    acc = acc ++ [char]

    cond do
      # Inside string: handle escapes
      in_str and escaped ->
        walk_json(rest, depth, true, false, acc)

      in_str and char == "\\" ->
        walk_json(rest, depth, true, true, acc)

      in_str and char == "\"" ->
        walk_json(rest, depth, false, false, acc)

      in_str ->
        walk_json(rest, depth, true, false, acc)

      # Outside string
      char == "\"" ->
        walk_json(rest, depth, true, false, acc)

      char == "{" ->
        walk_json(rest, depth + 1, false, false, acc)

      char == "}" and depth == 1 ->
        {:ok, acc}

      char == "}" ->
        walk_json(rest, depth - 1, false, false, acc)

      true ->
        walk_json(rest, depth, false, false, acc)
    end
  end

  defp maybe_put_openai_json_schema(generation_opts, opts) do
    if openai_model?(opts) do
      Keyword.put(generation_opts, :provider_options, openai_provider_options(generation_opts))
    else
      generation_opts
    end
  end

  defp openai_provider_options(generation_opts) do
    generation_opts
    |> Keyword.get(:provider_options, [])
    |> Keyword.put(:openai_structured_output_mode, :json_schema)
  end

  defp openai_model?(opts) do
    case Keyword.get(opts, :model_metadata) do
      %{provider: :openai} ->
        true

      _ ->
        case Keyword.get(opts, :model) do
          "openai:" <> _rest -> true
          _ -> false
        end
    end
  end
end
