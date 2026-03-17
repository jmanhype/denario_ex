defmodule DenarioExUI.PhaseEvents do
  @moduledoc false

  alias Phoenix.PubSub

  @pubsub DenarioExUI.PubSub

  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(project_dir) do
    PubSub.subscribe(@pubsub, topic(project_dir))
  end

  @spec unsubscribe(String.t()) :: :ok
  def unsubscribe(project_dir) do
    PubSub.unsubscribe(@pubsub, topic(project_dir))
  end

  @spec broadcast(String.t(), map()) :: :ok | {:error, term()}
  def broadcast(project_dir, event) do
    PubSub.broadcast(@pubsub, topic(project_dir), {:phase_event, normalize_event(event)})
  end

  @spec new_run_id() :: String.t()
  def new_run_id do
    "run-" <> Integer.to_string(System.unique_integer([:positive, :monotonic]))
  end

  defp topic(project_dir) do
    project_dir
    |> Path.expand()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
    |> then(&("project_runs:" <> &1))
  end

  defp normalize_event(event) do
    %{
      run_id: Map.get(event, :run_id) || Map.get(event, "run_id"),
      phase: Map.get(event, :phase) || Map.get(event, "phase"),
      status: Map.get(event, :status) || Map.get(event, "status") || :running,
      kind: Map.get(event, :kind) || Map.get(event, "kind") || :progress,
      message: Map.get(event, :message) || Map.get(event, "message") || "",
      progress: normalize_progress(Map.get(event, :progress) || Map.get(event, "progress")),
      stage: Map.get(event, :stage) || Map.get(event, "stage"),
      at: Map.get(event, :at) || Map.get(event, "at") || timestamp(),
      snapshot: Map.get(event, :snapshot) || Map.get(event, "snapshot"),
      metadata: Map.get(event, :metadata) || Map.get(event, "metadata") || %{}
    }
  end

  defp normalize_progress(nil), do: 0
  defp normalize_progress(progress) when is_integer(progress), do: min(max(progress, 0), 100)

  defp normalize_progress(progress) when is_float(progress),
    do: progress |> round() |> normalize_progress()

  defp normalize_progress(_progress), do: 0

  defp timestamp do
    NaiveDateTime.utc_now()
    |> NaiveDateTime.truncate(:second)
    |> to_string()
  end
end
