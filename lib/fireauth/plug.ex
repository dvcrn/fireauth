defmodule Fireauth.Plug do
  @moduledoc """
  Plug middleware that:

  1. Proxies (or serves) Firebase auth helper files at `/__/auth/*` (optional).
  2. If `Authorization: Bearer <id_token>` is present, verifies the token and
     attaches claims to `conn.assigns`.

  This is intended to match the MCPNest pattern:
  - In production, set Firebase `authDomain` to your app's domain and serve the
    helper files from the same origin to avoid cross-origin storage issues.
  - In development, you can continue using popup mode, but hosted files still work.
  """

  import Plug.Conn

  alias Fireauth.Plug.FirebaseAuthProxy
  alias Fireauth.Plug.HostedAuthFiles

  @behaviour Plug

  @type assigns_key :: atom()

  @impl true
  def init(opts) when is_list(opts) do
    opts
    |> Keyword.put_new(:serve_hosted_auth?, true)
    |> Keyword.put_new(:hosted_auth_mode, :proxy)
    |> Keyword.put_new(:assigns_key, :fireauth)
    |> Keyword.put_new(:on_invalid_token, :ignore)
  end

  @impl true
  def call(conn, opts) do
    conn =
      if Keyword.get(opts, :serve_hosted_auth?, true) do
        case Keyword.get(opts, :hosted_auth_mode, :proxy) do
          :proxy ->
            conn = FirebaseAuthProxy.call(conn, opts)
            if conn.halted, do: conn, else: HostedAuthFiles.call(conn, opts)

          :static ->
            HostedAuthFiles.call(conn, opts)

          _ ->
            conn
        end
      else
        conn
      end

    if conn.halted do
      conn
    else
      maybe_attach_firebase_claims(conn, opts)
    end
  end

  defp maybe_attach_firebase_claims(%Plug.Conn{} = conn, opts) do
    case bearer_token(conn) do
      nil ->
        conn

      token ->
        case Fireauth.verify_id_token(token, opts) do
          {:ok, claims} ->
            assigns_key = Keyword.fetch!(opts, :assigns_key)

            fireauth = %{
              token: token,
              claims: claims,
              user_attrs: Fireauth.claims_to_user_attrs(claims)
            }

            assign(conn, assigns_key, fireauth)

          {:error, reason} ->
            case Keyword.get(opts, :on_invalid_token, :ignore) do
              :ignore ->
                conn

              :unauthorized ->
                conn
                |> put_resp_header("www-authenticate", ~s(Bearer realm="firebase"))
                |> send_resp(401, "unauthorized")
                |> halt()

              {:assign_error, error_key} when is_atom(error_key) ->
                assign(conn, error_key, reason)

              _ ->
                conn
            end
        end
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] when token != "" -> token
      ["bearer " <> token | _] when token != "" -> token
      _ -> nil
    end
  end
end
