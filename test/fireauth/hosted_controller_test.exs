defmodule Fireauth.HostedControllerTest do
  use ExUnit.Case
  use Plug.Test

  import Mox

  alias Fireauth.HostedController

  setup :verify_on_exit!

  setup do
    Mox.set_mox_global()
    Application.put_env(:fireauth, :firebase_upstream_adapter, Fireauth.FirebaseUpstreamMock)

    on_exit(fn ->
      Application.delete_env(:fireauth, :firebase_upstream_adapter)
    end)

    :ok
  end

  test "proxies hosted auth action html upstream" do
    expect(Fireauth.FirebaseUpstreamMock, :fetch, fn "proj", "/__/auth/action", "mode=signIn" ->
      {:ok,
       %{
         status: 200,
         headers: [{"content-type", "text/html"}],
         body: "<html>proxied action</html>"
       }}
    end)

    conn =
      conn(:get, "/__/auth/action?mode=signIn")
      |> HostedController.call(HostedController.init(project_id: "proj"))

    assert conn.halted
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") |> List.first() =~ "text/html"
    assert conn.resp_body =~ "proxied action"
  end

  test "proxies hosted auth action script upstream" do
    expect(Fireauth.FirebaseUpstreamMock, :fetch, fn "proj", "/__/auth/action.js", nil ->
      {:ok,
       %{
         status: 200,
         headers: [{"content-type", "text/javascript"}],
         body: "console.log('proxied action.js')"
       }}
    end)

    conn =
      conn(:get, "/__/auth/action.js")
      |> HostedController.call(HostedController.init(project_id: "proj"))

    assert conn.halted
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") |> List.first() =~ "text/javascript"
    assert conn.resp_body =~ "proxied action.js"
  end

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
