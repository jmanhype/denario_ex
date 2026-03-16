defmodule DenarioEx.LLM do
  @moduledoc """
  Normalizes Denario model inputs through LLMDB/ReqLLM.
  """

  @default_max_output_tokens 16_384

  @default_specs %{
    "gemini-2.0-flash" => {"google:gemini-2.0-flash", 0.7},
    "gemini-2.5-flash" => {"google:gemini-2.5-flash", 0.7},
    "gemini-2.5-pro" => {"google:gemini-2.5-pro", 0.7},
    "o3-mini" => {"openai:o3-mini", nil},
    "gpt-4o" => {"openai:gpt-4o", 0.5},
    "gpt-4.1" => {"openai:gpt-4.1", 0.5},
    "gpt-4.1-mini" => {"openai:gpt-4.1-mini", 0.5},
    "gpt-4o-mini" => {"openai:gpt-4o-mini", 0.5},
    "gpt-4.5" => {"openai:gpt-4.5-preview", 0.5},
    "gpt-5" => {"openai:gpt-5", nil},
    "gpt-5-mini" => {"openai:gpt-5-mini", nil}
  }

  @provider_aliases %{
    "anthropic" => :anthropic,
    "deepseek" => :deepseek,
    "google" => :google,
    "google-vertex" => :google_vertex,
    "google_vertex" => :google_vertex,
    "groq" => :groq,
    "mistral" => :mistral,
    "ollama" => :ollama,
    "openai" => :openai,
    "openrouter" => :openrouter,
    "perplexity" => :perplexity,
    "xai" => :xai
  }

  @enforce_keys [:spec, :model, :provider, :max_output_tokens]
  defstruct [:spec, :model, :provider, :max_output_tokens, :temperature]

  @type t :: %__MODULE__{
          spec: String.t(),
          model: LLMDB.Model.t(),
          provider: atom(),
          max_output_tokens: pos_integer(),
          temperature: float() | nil
        }

  @spec parse(String.t() | t()) :: {:ok, t()}
  def parse(%__MODULE__{} = llm), do: {:ok, llm}

  def parse(name) when is_binary(name) do
    {spec, temperature} = normalize_spec(name)

    with {:ok, model} <- resolve_model(spec) do
      {:ok,
       %__MODULE__{
         spec: spec,
         model: model,
         provider: model.provider,
         max_output_tokens: max_output_tokens(model),
         temperature: temperature
       }}
    end
  end

  defp normalize_spec(name) do
    case Map.get(@default_specs, name) do
      {spec, temperature} ->
        {spec, temperature}

      nil ->
        spec =
          if String.contains?(name, [":", "@"]) do
            name
          else
            "openai:#{name}"
          end

        case parse_spec(spec) do
          {:ok, {provider, model_id}} ->
            {format_spec(provider, model_id), default_temperature(provider, model_id)}

          {:error, reason} ->
            raise ArgumentError, "invalid model spec: #{inspect(spec)} (#{inspect(reason)})"
        end
    end
  end

  defp resolve_model(spec) do
    case LLMDB.model(spec) do
      {:ok, model} ->
        {:ok, model}

      {:error, _reason} ->
        with {:ok, {provider, model_id}} <- parse_spec(spec) do
          ReqLLM.model(%{provider: provider, id: model_id})
        end
    end
  end

  defp max_output_tokens(%LLMDB.Model{limits: limits}) do
    case limits do
      %{output: output} when is_integer(output) and output > 0 -> output
      %{"output" => output} when is_integer(output) and output > 0 -> output
      _ -> @default_max_output_tokens
    end
  end

  defp default_temperature(provider, _model_id) when provider in [:google, :google_vertex],
    do: 0.7

  defp default_temperature(:openai, model_id) do
    if reasoning_model?(model_id), do: nil, else: 0.5
  end

  defp default_temperature(_provider, _model_id), do: 0.5

  defp reasoning_model?(model_id) do
    String.starts_with?(model_id, ["gpt-5", "o1", "o3", "o4"])
  end

  defp parse_spec(spec) do
    try do
      {:ok, LLMDB.parse!(spec)}
    rescue
      ArgumentError -> manual_parse_spec(spec)
    end
  end

  defp manual_parse_spec(spec) do
    cond do
      String.contains?(spec, ":") ->
        [provider_part, model_id] = String.split(spec, ":", parts: 2)
        build_spec(provider_part, model_id, spec)

      String.contains?(spec, "@") ->
        [model_id, provider_part] = String.split(spec, "@", parts: 2)
        build_spec(provider_part, model_id, spec)

      true ->
        {:error, :invalid_model_spec}
    end
  end

  defp build_spec(provider_part, model_id, spec) do
    provider_key = provider_part |> String.trim() |> String.downcase()
    model_id = String.trim(model_id)

    case Map.fetch(@provider_aliases, provider_key) do
      {:ok, provider} when model_id != "" ->
        {:ok, {provider, model_id}}

      _ ->
        {:error, {:invalid_model_spec, spec}}
    end
  end

  defp format_spec(provider, model_id) do
    try do
      LLMDB.format({provider, model_id})
    rescue
      _ -> "#{provider}:#{model_id}"
    end
  end
end
