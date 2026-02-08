defmodule Fireauth.Plug.FirebaseAuthProxyTest do
  use ExUnit.Case
  use Plug.Test

  import Mox

  alias Fireauth.FirebaseUpstream.Cache
  alias Fireauth.Plug.FirebaseAuthProxy

  setup :verify_on_exit!

  test "does not proxy unrelated paths" do
    conn = conn(:get, "/health") |> FirebaseAuthProxy.call(project_id: "x")
    refute conn.halted
  end

  setup do
    Mox.set_mox_global()
    Application.put_env(:fireauth, :firebase_upstream_adapter, Fireauth.FirebaseUpstreamMock)
    Cache.clear()

    on_exit(fn ->
      Application.delete_env(:fireauth, :firebase_upstream_adapter)
    end)

    :ok
  end

  test "serves proxied paths from cache when present" do
    :ok = Cache.clear()

    conn = conn(:get, "/__/auth/handler")
    key = {"myproj", "/__/auth/handler", nil}

    Cache.put(key, %{
      status: 200,
      headers: [{"content-type", "text/html"}],
      body: "<html>ok</html>",
      inserted_at_ms: System.system_time(:millisecond),
      ttl_ms: 60_000
    })

    conn2 =
      conn
      |> FirebaseAuthProxy.call(project_id: "myproj")

    assert conn2.halted
    assert conn2.status == 200
    assert get_resp_header(conn2, "content-type") |> List.first() =~ "text/html"
  end

  test "cache miss calls upstream adapter and caches the response (and receives project id)" do
    :ok = Cache.clear()

    expect(Fireauth.FirebaseUpstreamMock, :fetch, fn "myproj", "/__/auth/handler", "x=1" ->
      {:ok,
       %{
         status: 200,
         headers: [{"content-type", "text/html"}],
         body: "<html>upstream</html>"
       }}
    end)

    conn = conn(:get, "/__/auth/handler?x=1")

    conn2 =
      conn
      |> FirebaseAuthProxy.call(
        project_id: "myproj",
        firebase_cache_ttl_ms: 60_000
      )

    assert conn2.halted
    assert conn2.status == 200

    # Second request should be served from cache (no extra fetch message)
    _conn3 =
      conn
      |> FirebaseAuthProxy.call(
        project_id: "myproj",
        firebase_cache_ttl_ms: 60_000
      )
  end

  test "proxies /__/firebase/init.json from cache when present" do
    :ok = Cache.clear()

    conn = conn(:get, "/__/firebase/init.json")
    key = {"myproj", "/__/firebase/init.json", nil}

    Cache.put(key, %{
      status: 200,
      headers: [{"content-type", "application/json"}],
      body: ~s({"ok":true}),
      inserted_at_ms: System.system_time(:millisecond),
      ttl_ms: 60_000
    })

    conn2 =
      conn
      |> FirebaseAuthProxy.call(project_id: "myproj")

    assert conn2.halted
    assert conn2.status == 200
    assert get_resp_header(conn2, "content-type") |> List.first() =~ "application/json"
  end
end
