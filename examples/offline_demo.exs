case DenarioEx.OfflineDemo.run() do
  {:ok, _denario} ->
    :ok

  {:error, reason} ->
    IO.puts(:stderr, "offline demo failed: #{inspect(reason)}")
    System.halt(1)
end
