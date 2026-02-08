defmodule Fireauth.Plug.SessionCookiePlugTest do
  use ExUnit.Case
  use Plug.Test

  import Mox

  alias Fireauth.Claims
  alias Fireauth.Plug.SessionCookie, as: SessionCookiePlug

  setup do
    Mox.set_mox_global()

    Application.put_env(
      :fireauth,
      :session_cookie_validator_adapter,
      Fireauth.SessionCookieValidatorMock
    )

    on_exit(fn ->
      Application.delete_env(:fireauth, :session_cookie_validator_adapter)
    end)

    :ok
  end

  setup :verify_on_exit!

  test "assigns verified claims when session cookie is present" do
    cookie = "cookie.jwt.here"

    claims = %Claims{
      sub: "uid",
      aud: "test-proj",
      iss: "https://session.firebase.google.com/test-proj",
      user_id: "uid",
      identities: %{}
    }

    expect(Fireauth.SessionCookieValidatorMock, :verify_session_cookie, fn ^cookie, _opts ->
      {:ok, claims}
    end)

    conn =
      conn(:get, "/")
      |> put_req_cookie("session", cookie)
      |> SessionCookiePlug.call(SessionCookiePlug.init(project_id: "test-proj"))

    assert conn.assigns.fireauth.token == cookie
    assert conn.assigns.fireauth.claims.iss == "https://session.firebase.google.com/test-proj"
    assert %Fireauth.User{} = conn.assigns.fireauth.user_attrs
  end

  test "on_invalid_cookie :unauthorized returns 401" do
    expect(Fireauth.SessionCookieValidatorMock, :verify_session_cookie, fn "not-a-jwt", _opts ->
      {:error, :invalid_cookie_format}
    end)

    conn =
      conn(:get, "/")
      |> put_req_cookie("session", "not-a-jwt")
      |> SessionCookiePlug.call(
        SessionCookiePlug.init(project_id: "test-proj", on_invalid_cookie: :unauthorized)
      )

    assert conn.halted
    assert conn.status == 401
  end
end
