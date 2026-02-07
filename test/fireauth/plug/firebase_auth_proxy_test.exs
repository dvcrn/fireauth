defmodule Fireauth.Plug.FirebaseAuthProxyTest do
  use ExUnit.Case
  use Plug.Test

  alias Fireauth.FirebaseCache
  alias Fireauth.Plug.FirebaseAuthProxy

  defmodule TestUpstream do
    @behaviour Fireauth.FirebaseUpstream

    @impl true
    def fetch(project_id, path, query_string) do
      send(Process.get(:test_pid), {:fetch, project_id, path, query_string})

      {:ok,
       %{
         status: 200,
         headers: [{"content-type", "text/html"}],
         body: "<html>upstream</html>"
       }}
    end
  end

  test "does not proxy unrelated paths" do
    conn = conn(:get, "/health") |> FirebaseAuthProxy.call(project_id: "x")
    refute conn.halted
  end

  setup do
    prev = Application.get_env(:fireauth, :firebase_upstream_adapter)
    Application.put_env(:fireauth, :firebase_upstream_adapter, TestUpstream)
    Process.put(:test_pid, self())

    on_exit(fn ->
      Process.delete(:test_pid)
      if is_nil(prev) do
        Application.delete_env(:fireauth, :firebase_upstream_adapter)
      else
        Application.put_env(:fireauth, :firebase_upstream_adapter, prev)
      end
    end)

    :ok
  end

  test "serves proxied paths from cache when present" do
    :ok = FirebaseCache.ensure_started()
    :ok = FirebaseCache.clear()

    conn = conn(:get, "/__/auth/handler")
    key = {"myproj", "/__/auth/handler", nil}

    FirebaseCache.put(key, %{
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
    :ok = FirebaseCache.ensure_started()
    :ok = FirebaseCache.clear()

    conn = conn(:get, "/__/auth/handler?x=1")

    conn2 =
      conn
      |> FirebaseAuthProxy.call(
        project_id: "myproj",
        firebase_cache_ttl_ms: 60_000
      )

    assert conn2.halted
    assert conn2.status == 200
    assert_received {:fetch, "myproj", "/__/auth/handler", "x=1"}

    # Second request should be served from cache (no extra fetch message)
    _conn3 =
      conn
      |> FirebaseAuthProxy.call(
        project_id: "myproj",
        firebase_cache_ttl_ms: 60_000
      )

    refute_received {:fetch, "myproj", "/__/auth/handler", "x=1"}
  end

  test "proxies /__/firebase/init.json from cache when present" do
    :ok = FirebaseCache.ensure_started()
    :ok = FirebaseCache.clear()

    conn = conn(:get, "/__/firebase/init.json")
    key = {"myproj", "/__/firebase/init.json", nil}

    FirebaseCache.put(key, %{
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
