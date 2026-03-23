defmodule DenarioEx.SystemPdfRasterizerTest do
  use ExUnit.Case, async: false

  alias DenarioEx.SystemPdfRasterizer

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "denario_ex_rasterizer_#{System.unique_integer([:positive])}"
      )

    old_path = System.get_env("PATH")

    on_exit(fn ->
      if old_path, do: System.put_env("PATH", old_path)
      File.rm_rf(tmp_dir)
    end)

    {:ok, tmp_dir: tmp_dir}
  end

  test "rasterize/3 clears stale page images before collecting new output", %{tmp_dir: tmp_dir} do
    bin_dir = Path.join(tmp_dir, "bin")
    output_dir = Path.join(tmp_dir, "output")
    pdf_path = Path.join(tmp_dir, "paper.pdf")
    executable_path = Path.join(bin_dir, "pdftoppm")

    File.mkdir_p!(bin_dir)
    File.mkdir_p!(output_dir)
    File.write!(pdf_path, "fake pdf bytes")
    File.write!(Path.join(output_dir, "page-2.png"), "stale second page")

    File.write!(
      executable_path,
      """
      #!/bin/sh
      prefix="$5"
      printf 'fresh first page' > "${prefix}-1.png"
      exit 0
      """
    )

    File.chmod!(executable_path, 0o755)
    System.put_env("PATH", "#{bin_dir}:#{System.get_env("PATH")}")

    assert {:ok, paths} = SystemPdfRasterizer.rasterize(pdf_path, output_dir, dpi: 72)

    assert paths == [Path.join(output_dir, "page-1.png")]
    refute File.exists?(Path.join(output_dir, "page-2.png"))
  end
end
