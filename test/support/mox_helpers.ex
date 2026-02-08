defmodule Fireauth.Test.MoxHelpers do
  @moduledoc false

  def ok_html(body \\ "<html>ok</html>") do
    {:ok, %{status: 200, headers: [{"content-type", "text/html"}], body: body}}
  end
end
