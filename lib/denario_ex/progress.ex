defmodule DenarioEx.Progress do
  @moduledoc false

  @type callback :: (map() -> any())

  @spec emit(keyword(), map()) :: :ok
  def emit(opts, event) when is_list(opts), do: emit(Keyword.get(opts, :progress_callback), event)

  @spec emit(callback() | nil, map()) :: :ok
  def emit(nil, _event), do: :ok

  def emit(callback, event) when is_function(callback, 1) do
    callback.(normalize_event(event))
    :ok
  rescue
    _error -> :ok
  end

  def emit(_callback, _event), do: :ok

  defp normalize_event(event) do
    %{
      status: Map.get(event, :status, :running),
      kind: Map.get(event, :kind, :progress),
      message: Map.get(event, :message, ""),
      progress: normalize_progress(Map.get(event, :progress, 0)),
      stage: Map.get(event, :stage),
      metadata: Map.get(event, :metadata, %{})
    }
  end

  defp normalize_progress(progress) when is_integer(progress), do: min(max(progress, 0), 100)

  defp normalize_progress(progress) when is_float(progress),
    do: progress |> round() |> normalize_progress()

  defp normalize_progress(_progress), do: 0
end
