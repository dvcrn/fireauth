defmodule Fireauth.Plug.SessionCookie do
  @moduledoc """
  Plug middleware that verifies a Firebase session cookie and attaches claims to `conn.assigns`.

  This is intended for Phoenix browser pipelines / LiveView, where you want an
  httpOnly cookie session instead of accepting client-supplied `Authorization`
  headers on every request.
  """

  import Plug.Conn

  @behaviour Plug

  @type assigns_key :: atom()

  @impl true
  def init(opts) when is_list(opts) do
    opts
    |> Keyword.put_new(:cookie_name, "session")
    |> Keyword.put_new(:assigns_key, :fireauth)
    |> Keyword.put_new(:on_invalid_cookie, :ignore)
  end

  @impl true
  def call(conn, opts) do
    conn = fetch_cookies(conn)

    case cookie_value(conn, opts) do
      nil ->
        conn

      cookie ->
        verify_and_attach(conn, cookie, opts)
    end
  end

  defp cookie_value(conn, opts) do
    name = Keyword.fetch!(opts, :cookie_name)
    Map.get(conn.req_cookies, name)
  end

  defp verify_and_attach(conn, cookie, opts) do
    case Fireauth.verify_session_cookie(cookie, opts) do
      {:ok, claims} ->
        assigns_key = Keyword.fetch!(opts, :assigns_key)

        fireauth = %{
          token: cookie,
          claims: claims,
          user_attrs: Fireauth.claims_to_user_attrs(claims)
        }

        assign(conn, assigns_key, fireauth)

      {:error, reason} ->
        handle_invalid_cookie(conn, reason, opts)
    end
  end

  defp handle_invalid_cookie(conn, reason, opts) do
    case Keyword.get(opts, :on_invalid_cookie, :ignore) do
      :ignore ->
        conn

      :unauthorized ->
        conn
        |> send_resp(401, "unauthorized")
        |> halt()

      {:assign_error, error_key} when is_atom(error_key) ->
        assign(conn, error_key, reason)

      _ ->
        conn
    end
  end
end
