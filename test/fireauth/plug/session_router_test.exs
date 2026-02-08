defmodule Fireauth.Plug.SessionRouterTest do
  use ExUnit.Case
  use Plug.Test

  alias Fireauth.Plug.SessionRouter

  @opts SessionRouter.init(
          csrf_cookie_name: "fireauth_csrf",
          session_cookie_name: "session",
          cookie_secure: true,
          cookie_same_site: "Lax",
          valid_duration_s: 600,
          create_session_cookie_fun: &__MODULE__.create_cookie/2
        )

  test "GET /csrf sets csrf cookie and returns token" do
    conn =
      conn(:get, "/csrf")
      |> SessionRouter.call(@opts)

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") |> List.first() =~ "application/json"

    [set_cookie | _] = get_resp_header(conn, "set-cookie")
    assert set_cookie =~ "fireauth_csrf="
  end

  test "POST /session without csrf returns 403" do
    conn =
      conn(:post, "/session", Jason.encode!(%{"idToken" => "x"}))
      |> put_req_header("content-type", "application/json")
      |> SessionRouter.call(@opts)

    assert conn.status == 403
  end

  test "POST /session with csrf mints and sets httpOnly cookie" do
    csrf = "tok123"

    conn =
      conn(:post, "/session", Jason.encode!(%{"idToken" => "idtok", "csrfToken" => csrf}))
      |> put_req_header("content-type", "application/json")
      |> put_req_cookie("fireauth_csrf", csrf)
      |> SessionRouter.call(@opts)

    assert conn.status == 200

    set_cookies = get_resp_header(conn, "set-cookie")
    assert Enum.any?(set_cookies, &String.contains?(&1, "session=session-cookie-jwt"))
    assert Enum.any?(set_cookies, &String.contains?(&1, "HttpOnly"))
    assert Enum.any?(set_cookies, &String.contains?(&1, "max-age=600"))
  end

  def create_cookie(_id_token, _opts), do: {:ok, "session-cookie-jwt"}
end
