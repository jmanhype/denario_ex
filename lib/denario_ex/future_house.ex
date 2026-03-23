defmodule DenarioEx.FutureHouse do
  @moduledoc false

  @behaviour DenarioEx.FutureHouseClient

  alias DenarioEx.{KeyManager, Progress, Text}

  @default_base_url "https://api.platform.edisonscientific.com"
  @default_job_name "job-futurehouse-paperqa3-precedent"
  @default_timeout_ms 2_400_000
  @default_poll_interval_ms 5_000
  @terminal_statuses MapSet.new(["success", "fail", "cancelled", "truncated"])

  @impl true
  def run_owl_review(prompt, %KeyManager{} = keys, opts \\ []) do
    callback = Keyword.get(opts, :progress_callback)

    with api_key when is_binary(api_key) and api_key != "" <- keys.future_house,
         base_url = Keyword.get(opts, :base_url, @default_base_url),
         timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms),
         poll_interval_ms = Keyword.get(opts, :poll_interval_ms, @default_poll_interval_ms),
         job_name = Keyword.get(opts, :job_name, @default_job_name),
         {:ok, access_token} <- authenticate(base_url, api_key, callback),
         {:ok, task_id} <- create_task(base_url, access_token, prompt, job_name, callback),
         {:ok, result} <-
           poll_task(base_url, access_token, task_id, timeout_ms, poll_interval_ms, callback) do
      {:ok, result}
    else
      nil -> {:error, {:missing_api_key, :future_house}}
      {:error, _reason} = error -> error
    end
  end

  defp authenticate(base_url, api_key, callback) do
    Progress.emit(callback, %{
      kind: :progress,
      message: "Authenticating with the Edison platform.",
      progress: 18,
      stage: "futurehouse:auth"
    })

    request = Req.new(base_url: base_url)

    case Req.post(request, url: "/auth/login", json: %{api_key: api_key}) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        case fetch(body, "access_token") do
          token when is_binary(token) and token != "" -> {:ok, token}
          _ -> {:error, {:futurehouse_auth_failed, :missing_access_token, body}}
        end

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:futurehouse_auth_failed, status, body}}

      {:error, error} ->
        {:error, {:futurehouse_auth_failed, error}}
    end
  end

  defp create_task(base_url, access_token, prompt, job_name, callback) do
    Progress.emit(callback, %{
      kind: :progress,
      message: "Creating the FutureHouse precedent task.",
      progress: 32,
      stage: "futurehouse:create_task"
    })

    request =
      Req.new(
        base_url: base_url,
        headers: [{"authorization", "Bearer " <> access_token}]
      )

    case Req.post(request, url: "/v0.1/crows", json: %{name: job_name, query: prompt}) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        case fetch(body, "trajectory_id") do
          trajectory_id when is_binary(trajectory_id) and trajectory_id != "" ->
            {:ok, trajectory_id}

          _ ->
            {:error, {:futurehouse_task_creation_failed, :missing_trajectory_id, body}}
        end

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:futurehouse_task_creation_failed, status, body}}

      {:error, error} ->
        {:error, {:futurehouse_task_creation_failed, error}}
    end
  end

  defp poll_task(base_url, access_token, task_id, timeout_ms, poll_interval_ms, callback) do
    request =
      Req.new(
        base_url: base_url,
        headers: [{"authorization", "Bearer " <> access_token}]
      )

    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_poll(request, task_id, deadline, poll_interval_ms, callback)
  end

  defp do_poll(request, task_id, deadline, poll_interval_ms, callback) do
    with {:ok, lite_body} <- fetch_task(request, task_id, lite: true),
         status <- normalize_status(fetch(lite_body, "status")) do
      Progress.emit(callback, %{
        kind: :progress,
        message: "FutureHouse task status: #{status}.",
        progress: poll_progress(status),
        stage: "futurehouse:poll"
      })

      cond do
        MapSet.member?(@terminal_statuses, status) and status == "success" ->
          fetch_task(request, task_id, lite: false)

        MapSet.member?(@terminal_statuses, status) ->
          {:error, {:futurehouse_task_failed, status, lite_body}}

        System.monotonic_time(:millisecond) >= deadline ->
          {:error, {:futurehouse_timeout, task_id}}

        true ->
          Process.sleep(poll_interval_ms)
          do_poll(request, task_id, deadline, poll_interval_ms, callback)
      end
    end
  end

  defp fetch_task(request, task_id, opts) do
    lite? = Keyword.get(opts, :lite, false)

    case Req.get(request, url: "/v0.1/trajectories/#{task_id}", params: [lite: lite?]) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:futurehouse_fetch_failed, status, body}}

      {:error, error} ->
      {:error, {:futurehouse_fetch_failed, error}}
    end
  end

  defp normalize_status(status) when is_binary(status) do
    status
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_status(_status), do: ""

  defp poll_progress("queued"), do: 45
  defp poll_progress("running"), do: 60
  defp poll_progress("success"), do: 85
  defp poll_progress("fail"), do: 85
  defp poll_progress("cancelled"), do: 85
  defp poll_progress("truncated"), do: 85
  defp poll_progress(_status), do: 50

  defp fetch(map, key), do: Text.fetch(map, key)
end
