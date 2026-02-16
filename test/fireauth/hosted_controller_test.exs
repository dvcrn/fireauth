defmodule Fireauth.HostedControllerTest do
  use ExUnit.Case
  use Plug.Test

  alias Fireauth.HostedController

  test "serves snippet-based handler html" do
    conn =
      conn(:get, "/__/auth/handler")
      |> HostedController.call(HostedController.init([]))

    assert conn.halted
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") |> List.first() =~ "text/html"
    assert conn.resp_body =~ "fireauth.oauthhelper.widget.initialize()"
  end

  test "serves snippet-based iframe html" do
    conn =
      conn(:get, "/__/auth/iframe")
      |> HostedController.call(HostedController.init([]))

    assert conn.halted
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") |> List.first() =~ "text/html"
    assert conn.resp_body =~ "fireauth.iframe.AuthRelay.initialize()"
  end

  test "serves bundled js assets for non-html hosted files" do
    conn =
      conn(:get, "/__/auth/handler.js")
      |> HostedController.call(HostedController.init([]))

    assert conn.halted
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") |> List.first() =~ "text/javascript"
  end

  test "serves firebase init.json from config" do
    conn =
      conn(:get, "/__/firebase/init.json")
      |> HostedController.call(
        HostedController.init(
          firebase_web_config: %{
            "apiKey" => "key",
            "projectId" => "proj",
            "appId" => "app"
          }
        )
      )

    assert conn.halted
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") |> List.first() =~ "application/json"
    assert conn.resp_body =~ "\"projectId\":\"proj\""
  end
end
