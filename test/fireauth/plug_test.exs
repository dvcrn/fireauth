defmodule Fireauth.PlugTest do
  use ExUnit.Case
  use Plug.Test

  import Mox

  alias Fireauth.Claims
  alias Fireauth.FirebaseUpstream.Cache
  alias Fireauth.Plug, as: FireauthPlug

  setup do
    Mox.set_mox_global()
    Application.put_env(:fireauth, :token_validator_adapter, Fireauth.TokenValidatorMock)
    Application.put_env(:fireauth, :firebase_upstream_adapter, Fireauth.FirebaseUpstreamMock)
    Cache.clear()

    on_exit(fn ->
      Application.delete_env(:fireauth, :token_validator_adapter)
      Application.delete_env(:fireauth, :firebase_upstream_adapter)
    end)

    :ok
  end

  setup :verify_on_exit!

  defmodule CallbackController do
    import Plug.Conn

    def handler(conn, _params) do
      conn
      |> put_resp_content_type("text/html")
      |> send_resp(200, "<html>custom handler</html>")
      |> halt()
    end
  end

  test "assigns verified claims when bearer token is present" do
    claims = %Claims{
      sub: "uid",
      aud: "proj",
      iss: "https://securetoken.google.com/proj",
      identities: %{}
    }

    expect(Fireauth.TokenValidatorMock, :verify_id_token, fn "tok", _opts ->
      {:ok, claims}
    end)

    conn =
      conn(:get, "/")
      |> put_req_header("authorization", "Bearer tok")
      |> FireauthPlug.call(FireauthPlug.init([]))

    assert conn.assigns.fireauth.claims == claims
    assert conn.assigns.fireauth.token == "tok"
    assert %Fireauth.User{} = conn.assigns.fireauth.user
  end

  test "sets default empty struct when bearer token is absent" do
    conn =
      conn(:get, "/")
      |> FireauthPlug.call(FireauthPlug.init([]))

    assert conn.assigns.fireauth == %Fireauth{user: nil, claims: nil, token: nil}
  end

  test "on_invalid_token :unauthorized returns 401" do
    expect(Fireauth.TokenValidatorMock, :verify_id_token, fn "bad", _opts ->
      {:error, :invalid_signature}
    end)

    conn =
      conn(:get, "/")
      |> put_req_header("authorization", "Bearer bad")
      |> FireauthPlug.call(FireauthPlug.init(on_invalid_token: :unauthorized))

    assert conn.halted
    assert conn.status == 401
  end

  test "falls back to default_controller for managed callback paths" do
    conn =
      conn(:get, "/__/auth/handler")
      |> FireauthPlug.call(FireauthPlug.init(project_id: "myproj"))

    assert conn.halted
    assert conn.status == 200
    assert conn.resp_body =~ "fireauth.oauthhelper.widget.initialize()"
  end

  test "callback_overrides dispatches to tuple controller action" do
    conn =
      conn(:get, "/__/auth/handler")
      |> FireauthPlug.call(
        FireauthPlug.init(
          callback_overrides: %{
            "/__/auth/handler" => {CallbackController, :handler}
          }
        )
      )

    assert conn.halted
    assert conn.status == 200
    assert conn.resp_body =~ "custom handler"
  end

  test "callback_overrides supports plug module targets" do
    :ok = Cache.clear()

    expect(Fireauth.FirebaseUpstreamMock, :fetch, fn "myproj", "/__/firebase/init.json", nil ->
      {:ok,
       %{status: 200, headers: [{"content-type", "application/json"}], body: ~s({"ok":true})}}
    end)

    conn =
      conn(:get, "/__/firebase/init.json")
      |> FireauthPlug.call(
        FireauthPlug.init(
          project_id: "myproj",
          callback_overrides: %{
            "/__/firebase/init.json" => Fireauth.ProxyController
          }
        )
      )

    assert conn.halted
    assert conn.status == 200
    assert conn.resp_body == ~s({"ok":true})
  end

  test "callback_overrides falls back to default_controller for unlisted managed path" do
    conn =
      conn(:get, "/__/auth/iframe")
      |> FireauthPlug.call(
        FireauthPlug.init(
          callback_overrides: %{
            "/__/auth/handler" => Fireauth.HostedController
          }
        )
      )

    assert conn.halted
    assert conn.status == 200
  end

  test "default_controller nil disables fallback behavior" do
    conn =
      conn(:get, "/__/auth/iframe")
      |> FireauthPlug.call(
        FireauthPlug.init(
          callback_overrides: %{
            "/__/auth/handler" => Fireauth.HostedController
          },
          default_controller: nil
        )
      )

    refute conn.halted
  end
end
