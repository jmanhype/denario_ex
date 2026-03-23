defmodule DenarioEx.TextTest do
  use ExUnit.Case, async: true

  alias DenarioEx.Text

  test "extract_block_or_fallback returns wrapped content when block markers exist" do
    assert {:ok, "hello"} =
             Text.extract_block_or_fallback("\\begin{SUMMARY}hello\\end{SUMMARY}", "SUMMARY")
  end

  test "extract_block_or_fallback returns cleaned raw text when block markers are missing" do
    assert {:ok, "plain summary text"} =
             Text.extract_block_or_fallback("plain summary text", "SUMMARY")
  end

  test "fetch reads atom-key maps without creating new atoms for missing keys" do
    unique_key = "denario_missing_key_#{System.unique_integer([:positive])}"

    assert Text.fetch(%{existing_key: "value"}, "existing_key") == "value"
    assert Text.fetch(%{}, unique_key) == nil

    assert_raise ArgumentError, fn ->
      String.to_existing_atom(unique_key)
    end
  end

  test "clean_section removes xml-style wrapper tags for the requested section" do
    assert Text.clean_section("<SUMMARY>hello</SUMMARY>", "SUMMARY") == "hello"
  end
end
