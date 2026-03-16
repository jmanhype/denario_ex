defmodule DenarioEx.PythonExecutor do
  @moduledoc """
  Executes generated Python scripts inside a workflow workspace.
  """

  @behaviour DenarioEx.CodeExecutor

  @impl true
  def execute(code, opts) do
    work_dir = Keyword.fetch!(opts, :work_dir)
    step_id = Keyword.get(opts, :step_id, "step")
    attempt = Keyword.get(opts, :attempt, 1)
    python_command = Keyword.get(opts, :python_command, default_python_command())
    timeout_ms = Keyword.get(opts, :timeout_ms, 60_000)
    script_name = "#{step_id}_attempt_#{attempt}.py"
    script_path = Path.join(work_dir, script_name)

    File.mkdir_p!(work_dir)
    File.write!(script_path, code)

    try do
      task =
        Task.async(fn ->
          System.cmd(
            python_command,
            [script_path],
            cd: work_dir,
            env: execution_env(),
            stderr_to_stdout: true
          )
        end)

      case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
        {:ok, {output, 0}} ->
          {:ok,
           %{
             "status" => 0,
             "output" => output,
             "script_path" => script_path,
             "generated_files" => collect_generated_files(work_dir)
           }}

        {:ok, {output, status}} ->
          {:error,
           %{
             "status" => status,
             "output" => output,
             "script_path" => script_path
           }}

        nil ->
          {:error,
           %{
             "status" => 124,
             "output" => "Python execution timed out after #{timeout_ms} ms",
             "script_path" => script_path
           }}
      end
    rescue
      error ->
        {:error,
         %{
           "status" => 127,
           "output" => Exception.message(error),
           "script_path" => script_path
         }}
    end
  end

  defp default_python_command do
    [
      System.get_env("DENARIO_EX_PYTHON"),
      virtual_env_python()
      | local_venv_candidates()
    ]
    |> Enum.find(&(is_binary(&1) and File.exists?(&1)))
    |> case do
      nil ->
        cond do
          System.find_executable("python3") -> "python3"
          true -> "python"
        end

      python ->
        python
    end
  end

  defp virtual_env_python do
    case System.get_env("VIRTUAL_ENV") do
      nil -> nil
      path -> Path.join(path, "bin/python")
    end
  end

  defp local_venv_candidates do
    [File.cwd!(), __DIR__]
    |> Enum.flat_map(fn start_dir ->
      start_dir
      |> parent_directories()
      |> Enum.map(&Path.join(&1, ".venv/bin/python"))
    end)
    |> Enum.uniq()
  end

  defp parent_directories(start_dir) do
    start_dir = Path.expand(start_dir)

    Stream.unfold(start_dir, fn
      nil ->
        nil

      dir ->
        parent = Path.dirname(dir)

        next =
          if parent == dir do
            nil
          else
            parent
          end

        {dir, next}
    end)
    |> Enum.to_list()
  end

  defp collect_generated_files(work_dir) do
    extensions = ["png", "jpg", "jpeg", "pdf", "svg"]

    extensions
    |> Enum.flat_map(fn ext -> Path.wildcard(Path.join(work_dir, "**/*.#{ext}")) end)
    |> Enum.uniq()
  end

  defp execution_env do
    [
      {"MPLBACKEND", "Agg"},
      {"PYTHONUNBUFFERED", "1"}
    ]
  end
end
