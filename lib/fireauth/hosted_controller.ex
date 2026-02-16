defmodule Fireauth.HostedController do
  @moduledoc """
  Plug-style controller for Firebase hosted auth callback files.

  - `"/__/auth/handler"` and `"/__/auth/iframe"` are rendered from
    `Fireauth.Snippets` so consumers can reuse the same bootstrap contract.
  - All other hosted auth files are served from embedded static assets.
  """

  @behaviour Plug

  import Plug.Conn

  require Logger

  alias Fireauth.Plug.FirebaseInitJson
  alias Fireauth.Plug.HostedAuthFiles
  alias Fireauth.Snippets

  @impl true
  def init(opts) when is_list(opts), do: opts

  @impl true
  def call(%Plug.Conn{request_path: "/__/auth/handler"} = conn, _opts)
      when conn.method in ["GET", "HEAD"] do
    Logger.debug("fireauth: hosted_controller serving snippet handler path=/__/auth/handler")

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, Snippets.hosted_auth_handler_document())
    |> halt()
  end

  def call(%Plug.Conn{request_path: "/__/auth/iframe"} = conn, _opts)
      when conn.method in ["GET", "HEAD"] do
    Logger.debug("fireauth: hosted_controller serving snippet iframe path=/__/auth/iframe")

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, Snippets.hosted_auth_iframe_document())
    |> halt()
  end

  def call(%Plug.Conn{request_path: "/__/firebase/init.json"} = conn, opts)
      when conn.method in ["GET", "HEAD"] do
    Logger.debug("fireauth: hosted_controller serving init.json path=/__/firebase/init.json")
    FirebaseInitJson.call(conn, opts)
  end

  def call(conn, opts) do
    Logger.debug("fireauth: hosted_controller serving bundled file path=#{conn.request_path}")
    HostedAuthFiles.call(conn, opts)
  end
end
