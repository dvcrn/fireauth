defmodule Fireauth.FirebaseUpstream do
  @moduledoc """
  Adapter interface for fetching Firebase hosted helper files.

  This exists to make `Fireauth.Plug.FirebaseAuthProxy` easy to test without
  performing real network calls.

  Configure the adapter via:

  `config :fireauth, :firebase_upstream_adapter, Fireauth.FirebaseUpstream.Firebase`
  """

  @type headers :: [{String.t(), String.t()}]

  @typedoc """
  Response from upstream.

  Headers should be string key/value pairs.
  """
  @type response :: %{status: pos_integer(), headers: headers(), body: binary()}

  @callback fetch(project_id :: String.t(), path :: String.t(), query_string :: String.t() | nil) ::
              {:ok, response()} | {:error, term()}

  @spec fetch(String.t(), String.t(), String.t() | nil) :: {:ok, response()} | {:error, term()}
  def fetch(project_id, path, query_string \\ nil)
      when is_binary(project_id) and is_binary(path) do
    adapter().fetch(project_id, normalize_path(path), query_string)
  end

  defp normalize_path("/" <> _ = path), do: path
  defp normalize_path(path) when is_binary(path), do: "/" <> path

  defp adapter do
    Application.get_env(:fireauth, :firebase_upstream_adapter, Fireauth.FirebaseUpstream.Firebase)
  end
end
