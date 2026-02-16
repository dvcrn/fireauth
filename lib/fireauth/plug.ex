defmodule Fireauth.Plug do
  @moduledoc """
  Plug middleware that:

  1. Routes Firebase hosted callback paths via `:callback_overrides` (optional).
  2. If `Authorization: Bearer <id_token>` is present, verifies the token and
     attaches claims to `conn.assigns`.

  This is intended to match the MCPNest pattern:
  - In production, set Firebase `authDomain` to your app's domain and serve the
    helper files from the same origin to avoid cross-origin storage issues.
  - In development, you can continue using popup mode, but hosted files still work.

  ## Hosted callback overrides

  You can route exact callback paths with `:callback_overrides`:

      plug Fireauth.Plug,
        callback_overrides: %{
          "/__/auth/handler" => {MyAppWeb.FirebaseHostedAuthController, :handler},
          "/__/firebase/init.json" => Fireauth.ProxyController
        }

  When `:callback_overrides` is present, only listed paths are handled by this
  plug. Unlisted managed callback paths fall back to `:default_controller`
  (defaults to `Fireauth.HostedController`). Set `default_controller: nil` to
  disable fallback.
  """

  import Plug.Conn

  require Logger

  @behaviour Plug

  @type assigns_key :: atom()
  @type callback_override :: module() | {module(), atom()}
  @type callback_overrides :: %{optional(String.t()) => callback_override()}
  @type default_controller :: callback_override() | nil

  @impl true
  def init(opts) when is_list(opts) do
    opts
    |> Keyword.put_new(:assigns_key, :fireauth)
    |> Keyword.put_new(:on_invalid_token, :ignore)
    |> Keyword.put_new(:default_controller, Fireauth.HostedController)
  end

  @impl true
  def call(conn, opts) do
    conn = maybe_serve_hosted_auth(conn, opts)

    if conn.halted do
      conn
    else
      maybe_attach_firebase_claims(conn, opts)
    end
  end

  defp maybe_serve_hosted_auth(conn, opts) do
    case fetch_callback_overrides(opts) do
      {:ok, overrides} ->
        route_callback_override(conn, opts, overrides)

      :error ->
        maybe_log_ignored_legacy_mode(opts)
        maybe_dispatch_default_controller(conn, opts)
    end
  end

  defp maybe_log_ignored_legacy_mode(opts) do
    if Keyword.has_key?(opts, :hosted_auth_mode) do
      Logger.debug(
        "fireauth: hosted_auth_mode is ignored; use callback_overrides for hosted callback routing"
      )
    end
  end

  defp fetch_callback_overrides(opts) do
    case Keyword.fetch(opts, :callback_overrides) do
      {:ok, overrides} when is_map(overrides) ->
        Logger.debug("fireauth: callback_overrides enabled count=#{map_size(overrides)}")
        {:ok, overrides}

      {:ok, invalid} ->
        Logger.debug(
          "fireauth: callback_overrides ignored invalid_value=#{inspect(invalid)} (expected map)"
        )

        :error

      _ ->
        :error
    end
  end

  defp route_callback_override(conn, opts, overrides) do
    case Map.get(overrides, conn.request_path) do
      nil ->
        maybe_dispatch_default_controller(conn, opts)

      override ->
        Logger.debug(
          "fireauth: callback_overrides match path=#{conn.request_path} target=#{inspect(override)}"
        )

        dispatch_callback_override(conn, override, opts)
    end
  end

  @managed_callback_paths MapSet.new([
                            "/__/auth/handler",
                            "/__/auth/handler.js",
                            "/__/auth/experiments.js",
                            "/__/auth/iframe",
                            "/__/auth/iframe.js",
                            "/__/auth/links",
                            "/__/auth/links.js",
                            "/__/firebase/init.json"
                          ])

  defp maybe_dispatch_default_controller(conn, opts) do
    if MapSet.member?(@managed_callback_paths, conn.request_path) do
      case Keyword.get(opts, :default_controller) do
        nil ->
          Logger.debug(
            "fireauth: callback_overrides no_match path=#{conn.request_path} method=#{conn.method} default_controller=nil"
          )

          conn

        false ->
          Logger.debug(
            "fireauth: callback_overrides no_match path=#{conn.request_path} method=#{conn.method} default_controller=false"
          )

          conn

        default_controller ->
          Logger.debug(
            "fireauth: callback_overrides no_match path=#{conn.request_path} method=#{conn.method} falling_back_to=#{inspect(default_controller)}"
          )

          dispatch_callback_override(conn, default_controller, opts)
      end
    else
      conn
    end
  end

  defp dispatch_callback_override(conn, module, opts) when is_atom(module) do
    call_plug_module(conn, module, opts)
  end

  defp dispatch_callback_override(conn, {module, action}, _opts)
       when is_atom(module) and is_atom(action) do
    call_controller_action(conn, module, action)
  end

  defp dispatch_callback_override(conn, invalid_override, _opts) do
    Logger.debug(
      "fireauth: callback override ignored invalid_target=#{inspect(invalid_override)} path=#{conn.request_path}"
    )

    conn
  end

  defp call_plug_module(conn, module, opts) do
    if Code.ensure_loaded?(module) and function_exported?(module, :call, 2) do
      Logger.debug(
        "fireauth: dispatching callback override to plug module=#{inspect(module)} path=#{conn.request_path}"
      )

      init_opts =
        if function_exported?(module, :init, 1) do
          module.init(opts)
        else
          opts
        end

      module.call(conn, init_opts)
    else
      Logger.debug(
        "fireauth: callback override module not callable module=#{inspect(module)} path=#{conn.request_path}"
      )

      conn
    end
  end

  defp call_controller_action(conn, module, action) do
    if Code.ensure_loaded?(module) and function_exported?(module, action, 2) do
      Logger.debug(
        "fireauth: dispatching callback override to action module=#{inspect(module)} action=#{action} path=#{conn.request_path}"
      )

      conn = Plug.Conn.fetch_query_params(conn)
      apply(module, action, [conn, conn.params])
    else
      Logger.debug(
        "fireauth: callback action not callable module=#{inspect(module)} action=#{action} path=#{conn.request_path}"
      )

      conn
    end
  end

  defp maybe_attach_firebase_claims(%Plug.Conn{} = conn, opts) do
    assigns_key = Keyword.fetch!(opts, :assigns_key)

    conn =
      if Map.has_key?(conn.assigns, assigns_key) do
        conn
      else
        assign(conn, assigns_key, %Fireauth{user: nil, claims: nil, token: nil})
      end

    case bearer_token(conn) do
      nil -> conn
      token -> verify_and_attach(conn, token, opts)
    end
  end

  defp verify_and_attach(conn, token, opts) do
    case Fireauth.verify_id_token(token, opts) do
      {:ok, claims} ->
        assigns_key = Keyword.fetch!(opts, :assigns_key)

        user_attrs = Fireauth.claims_to_user_attrs(claims)

        fireauth = %Fireauth{
          token: token,
          claims: claims,
          user: user_attrs
        }

        assign(conn, assigns_key, fireauth)

      {:error, reason} ->
        handle_invalid_token(conn, reason, opts)
    end
  end

  defp handle_invalid_token(conn, reason, opts) do
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

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] when token != "" -> token
      ["bearer " <> token | _] when token != "" -> token
      _ -> nil
    end
  end
end
