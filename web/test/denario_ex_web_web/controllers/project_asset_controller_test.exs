defmodule DenarioExUIWeb.ProjectAssetControllerTest do
  use DenarioExUIWeb.ConnCase, async: true

  test "missing required params return 400 instead of crashing", %{conn: conn} do
    conn = get(conn, ~p"/artifacts")
    assert response(conn, 400) == "Bad request"
  end
end
