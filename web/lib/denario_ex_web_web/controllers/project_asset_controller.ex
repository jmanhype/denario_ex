defmodule DenarioExUIWeb.ProjectAssetController do
  use DenarioExUIWeb, :controller

  alias DenarioEx.ArtifactRegistry

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"project_dir" => project_dir, "kind" => kind} = params) do
    with {:ok, path} <- resolve(project_dir, kind, params),
         true <- File.regular?(path) do
      conn
      |> put_resp_content_type(MIME.from_path(path) || "application/octet-stream")
      |> put_resp_header("content-disposition", ~s(inline; filename="#{Path.basename(path)}"))
      |> send_file(200, path)
    else
      false ->
        send_resp(conn, 404, "Not found")

      {:error, _reason} ->
        send_resp(conn, 400, "Bad request")
    end
  end

  defp resolve(project_dir, "paper_pdf", _params), do: project_artifact(project_dir, :paper_pdf)
  defp resolve(project_dir, "paper_tex", _params), do: project_artifact(project_dir, :paper_tex)
  defp resolve(project_dir, "referee_log", _params), do: referee_log(project_dir)

  defp resolve(project_dir, "plot", %{"name" => name}) do
    root = Path.expand(project_dir)
    plot_path = Path.join(ArtifactRegistry.plots_dir(root), Path.basename(name))
    ensure_inside(root, plot_path)
  end

  defp resolve(_project_dir, _kind, _params), do: {:error, :unsupported_asset}

  defp project_artifact(project_dir, artifact) do
    root = Path.expand(project_dir)
    ensure_inside(root, ArtifactRegistry.path(root, artifact))
  end

  defp referee_log(project_dir) do
    root = Path.expand(project_dir)
    log_path = Path.join(ArtifactRegistry.referee_output_dir(root), "referee.log")
    ensure_inside(root, log_path)
  end

  defp ensure_inside(root, path) do
    expanded_root = Path.expand(root)
    expanded_path = Path.expand(path)

    if expanded_path == expanded_root or String.starts_with?(expanded_path, expanded_root <> "/") do
      {:ok, expanded_path}
    else
      {:error, :invalid_path}
    end
  end
end
