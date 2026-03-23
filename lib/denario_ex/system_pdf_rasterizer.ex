defmodule DenarioEx.SystemPdfRasterizer do
  @moduledoc false

  @behaviour DenarioEx.PdfRasterizer

  @impl true
  def rasterize(pdf_path, output_dir, opts \\ []) do
    File.mkdir_p!(output_dir)
    clear_existing_pages(output_dir)

    cond do
      executable = System.find_executable("pdftoppm") ->
        rasterize_with_pdftoppm(executable, pdf_path, output_dir, opts)

      executable = System.find_executable("mutool") ->
        rasterize_with_mutool(executable, pdf_path, output_dir, opts)

      true ->
        {:error, :renderer_unavailable}
    end
  end

  defp clear_existing_pages(output_dir) do
    output_dir
    |> Path.join("page-*.png")
    |> Path.wildcard()
    |> Enum.each(&File.rm!/1)
  end

  defp rasterize_with_pdftoppm(executable, pdf_path, output_dir, opts) do
    dpi = Keyword.get(opts, :dpi, 200)
    prefix = Path.join(output_dir, "page")

    {_output, status} =
      System.cmd(executable, ["-png", "-r", Integer.to_string(dpi), pdf_path, prefix],
        stderr_to_stdout: true
      )

    if status == 0 do
      case Path.wildcard(Path.join(output_dir, "page-*.png")) do
        [] -> {:error, :renderer_produced_no_images}
        paths -> {:ok, Enum.sort(paths)}
      end
    else
      {:error, {:pdftoppm_failed, status}}
    end
  end

  defp rasterize_with_mutool(executable, pdf_path, output_dir, opts) do
    dpi = Keyword.get(opts, :dpi, 200)
    pattern = Path.join(output_dir, "page-%03d.png")

    {_output, status} =
      System.cmd(executable, ["draw", "-r", Integer.to_string(dpi), "-o", pattern, pdf_path],
        stderr_to_stdout: true
      )

    if status == 0 do
      case Path.wildcard(Path.join(output_dir, "page-*.png")) do
        [] -> {:error, :renderer_produced_no_images}
        paths -> {:ok, Enum.sort(paths)}
      end
    else
      {:error, {:mutool_failed, status}}
    end
  end
end
