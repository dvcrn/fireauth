defmodule Fireauth.IdentityToolkit.Client do
  @moduledoc false

  require Logger

  alias Fireauth.Admin.OAuth
  alias Fireauth.Config

  @identitytoolkit_base "https://identitytoolkit.googleapis.com/v1"

  @spec post(String.t(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def post(path, api_key, body, opts) do
    url = base_url(opts) <> "/" <> path <> "?key=" <> URI.encode_www_form(api_key)

    req_options =
      opts
      |> Keyword.get(:req_options, [])
      |> Keyword.put(:url, url)
      |> Keyword.put(:json, body)
      |> Keyword.put(:headers, auth_headers(opts))

    case Req.post(req_options) do
      {:ok, %{status: 200, body: %{} = response}} ->
        {:ok, response}

      {:ok, %{status: status, body: %{} = response}} ->
        {:error, {:identity_toolkit_error, path, status, response}}

      {:ok, %{status: status, body: body}} ->
        {:error, {:identity_toolkit_error, path, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec fetch_api_key(keyword()) :: {:ok, String.t()} | {:error, :missing_api_key}
  def fetch_api_key(opts) do
    case Config.firebase_api_key(opts) do
      api_key when is_binary(api_key) and api_key != "" -> {:ok, api_key}
      _ -> {:error, :missing_api_key}
    end
  end

  @spec compact_map(map()) :: map()
  def compact_map(map) do
    Enum.reduce(map, %{}, fn
      {_key, nil}, acc -> acc
      {_key, value}, acc when is_map(value) and map_size(value) == 0 -> acc
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end

  @spec blank_to_nil(term()) :: String.t() | nil
  def blank_to_nil(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  def blank_to_nil(_value), do: nil

  @spec blank?(term()) :: boolean()
  def blank?(value) when is_binary(value), do: String.trim(value) == ""

  defp base_url(opts) do
    Keyword.get(opts, :identity_toolkit_base_url, @identitytoolkit_base)
  end

  defp auth_headers(opts) do
    case Config.firebase_admin_service_account(opts) do
      nil ->
        []

      %{} = service_account ->
        case OAuth.fetch_access_token(service_account, opts) do
          {:ok, token} ->
            [{"authorization", "Bearer #{token}"}]

          {:error, reason} ->
            Logger.warning("fireauth: failed to fetch access token for Identity Toolkit request: #{inspect(reason)}")
            []
        end
    end
  end
end
