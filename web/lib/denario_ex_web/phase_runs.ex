defmodule DenarioExUI.PhaseRuns do
  @moduledoc false

  use Agent

  @type run_record :: %{
          pid: pid(),
          project_dir: String.t(),
          phase: String.t(),
          settings: map()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @spec put(String.t(), run_record()) :: :ok
  def put(run_id, record) do
    Agent.update(__MODULE__, &Map.put(&1, run_id, record))
  end

  @spec get(String.t()) :: run_record() | nil
  def get(run_id) do
    Agent.get(__MODULE__, &Map.get(&1, run_id))
  end

  @spec delete(String.t()) :: :ok
  def delete(run_id) do
    Agent.update(__MODULE__, &Map.delete(&1, run_id))
  end
end
