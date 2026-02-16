defmodule Fireauth.ProxyController do
  @moduledoc """
  Plug-style controller that proxies Firebase hosted auth files to upstream.
  """

  @behaviour Plug

  require Logger

  alias Fireauth.Plug.FirebaseAuthProxy

  @impl true
  def init(opts) when is_list(opts), do: opts

  @impl true
  def call(conn, opts) do
    Logger.debug("fireauth: proxy_controller forwarding path=#{conn.request_path}")
    FirebaseAuthProxy.call(conn, opts)
  end
end
