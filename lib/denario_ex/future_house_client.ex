defmodule DenarioEx.FutureHouseClient do
  @moduledoc false

  @callback run_owl_review(String.t(), DenarioEx.KeyManager.t(), keyword()) ::
              {:ok, map()} | {:error, term()}
end
