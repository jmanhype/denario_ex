defmodule DenarioEx.PdfRasterizer do
  @moduledoc false

  @callback rasterize(String.t(), String.t(), keyword()) :: {:ok, [String.t()]} | {:error, term()}
end
