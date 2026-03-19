defmodule Fireauth.SnippetsTest do
  use ExUnit.Case, async: true

  alias Fireauth.Snippets

  test "client preserves absolute http(s) return_to values" do
    html =
      Snippets.client(return_to: "https://digitalvibes.kikuyo.app/kikuyo")
      |> Phoenix.HTML.safe_to_string()

    assert html =~ ~s(returnTo: "https://digitalvibes.kikuyo.app/kikuyo")
    assert html =~ "function sanitizeReturnToDestination(value)"
    assert html =~ ~s(parsed.protocol === "http:" || parsed.protocol === "https:")
  end
end
