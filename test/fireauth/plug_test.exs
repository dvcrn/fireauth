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
      |> FireauthPlug.call(FireauthPlug.init(serve_hosted_auth?: false))

    assert conn.assigns.fireauth.claims == claims
    assert conn.assigns.fireauth.token == "tok"
    assert %Fireauth.User{} = conn.assigns.fireauth.user_attrs
  end

  test "does nothing when bearer token is absent" do
    conn =
      conn(:get, "/")
      |> FireauthPlug.call(FireauthPlug.init(serve_hosted_auth?: false))

    refute Map.has_key?(conn.assigns, :fireauth)
  end

  test "on_invalid_token :unauthorized returns 401" do
    expect(Fireauth.TokenValidatorMock, :verify_id_token, fn "bad", _opts ->
      {:error, :invalid_signature}
    end)

    conn =
      conn(:get, "/")
      |> put_req_header("authorization", "Bearer bad")
      |> FireauthPlug.call(
        FireauthPlug.init(serve_hosted_auth?: false, on_invalid_token: :unauthorized)
      )

    assert conn.halted
    assert conn.status == 401
  end

  test "proxies firebase hosted auth helper files (no token validation)" do
    :ok = Cache.clear()

    expect(Fireauth.FirebaseUpstreamMock, :fetch, fn "myproj", "/__/auth/handler", nil ->
      {:ok,
       %{status: 200, headers: [{"content-type", "text/html"}], body: "<html>handler</html>"}}
    end)

    conn =
      conn(:get, "/__/auth/handler")
      |> FireauthPlug.call(FireauthPlug.init(project_id: "myproj"))

    assert conn.halted
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") |> List.first() =~ "text/html"
  end
end
