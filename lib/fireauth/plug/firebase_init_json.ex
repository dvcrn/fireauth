defmodule Fireauth.Plug.FirebaseInitJson do
  @moduledoc """
  Serve `/__/firebase/init.json` from config.

  Firebase's redirect-mode helper (`/__/auth/handler`) fetches `init.json` from
  the same origin as the handler. Some projects do not serve this file from
  `*.firebaseapp.com`, so we support generating it locally.

  Configuration can be provided via:
  - `config :fireauth, :firebase_web_config, %{...}` (or `otp_app` override)
  - env vars `FIREBASE_API_KEY`, `FIREBASE_AUTH_DOMAIN`, `FIREBASE_PROJECT_ID`,
    `FIREBASE_STORAGE_BUCKET`, `FIREBASE_MESSAGING_SENDER_ID`, `FIREBASE_APP_ID`

  Required keys: `apiKey`, `projectId`, `appId`.
  """

  import Plug.Conn

  alias Fireauth.Config

  @behaviour Plug

  @required_keys ~w(apiKey projectId appId)

  @impl true
  def init(opts) when is_list(opts), do: opts

  @impl true
  def call(%Plug.Conn{request_path: "/__/firebase/init.json"} = conn, opts)
      when conn.method in ["GET", "HEAD"] do
    cfg = Config.firebase_web_config(opts) || %{}

    if valid_cfg?(cfg) do
      body = Map.put(cfg, "authDomain", auth_domain_for_conn(conn))

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(body))
      |> halt()
    else
      conn
    end
  end

  def call(conn, _opts), do: conn

  defp valid_cfg?(cfg) when is_map(cfg) do
    Enum.all?(@required_keys, fn key ->
      v = Map.get(cfg, key)
      is_binary(v) and String.trim(v) != ""
    end)
  end

  defp auth_domain_for_conn(conn) do
    host = conn.host
    port = conn.port

    include_port? =
      case {conn.scheme, port} do
        {:https, 443} -> false
        {:http, 80} -> false
        _ -> true
      end

    if include_port?, do: "#{host}:#{port}", else: host
  end
end
