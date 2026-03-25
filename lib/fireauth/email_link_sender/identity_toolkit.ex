defmodule Fireauth.EmailLinkSender.IdentityToolkit do
  @moduledoc false

  @behaviour Fireauth.EmailLinkSender

  alias Fireauth.Admin.OAuth
  alias Fireauth.Config
  alias Fireauth.EmailLinkSender.Result

  @identitytoolkit_base "https://identitytoolkit.googleapis.com/v1"

  @impl true
  @spec send_sign_in_link(String.t(), String.t(), keyword()) ::
          {:ok, Result.t()} | {:error, term()}
  def send_sign_in_link(email, continue_url, opts)
      when is_binary(email) and is_binary(continue_url) and is_list(opts) do
    with {:ok, normalized_email} <- normalize_email(email),
         {:ok, normalized_continue_url} <- normalize_continue_url(continue_url),
         {:ok, api_key} <- fetch_api_key(opts),
         {:ok, %{} = response} <-
           post(
             "accounts:sendOobCode",
             api_key,
             build_request_body(normalized_email, normalized_continue_url, opts),
             opts
           ) do
      {:ok,
       %Result{
         email: response["email"] || normalized_email,
         raw_response: response
       }}
    end
  end

  defp build_request_body(email, continue_url, opts) do
    %{
      "requestType" => "EMAIL_SIGNIN",
      "email" => email,
      "continueUrl" => continue_url,
      "canHandleCodeInApp" => true,
      "dynamicLinkDomain" => blank_to_nil(Keyword.get(opts, :dynamic_link_domain)),
      "iOSBundleId" => blank_to_nil(Keyword.get(opts, :ios_bundle_id)),
      "androidPackageName" => blank_to_nil(Keyword.get(opts, :android_package_name)),
      "androidInstallApp" => Keyword.get(opts, :android_install_app),
      "androidMinimumVersion" => blank_to_nil(Keyword.get(opts, :android_minimum_version)),
      "tenantId" => blank_to_nil(Keyword.get(opts, :tenant_id))
    }
    |> compact_map()
  end

  defp post(path, api_key, body, opts) do
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

  defp auth_headers(opts) do
    case Config.firebase_admin_service_account(opts) do
      nil ->
        []

      %{} = service_account ->
        case OAuth.fetch_access_token(service_account, opts) do
          {:ok, token} -> [{"authorization", "Bearer #{token}"}]
          {:error, _reason} -> []
        end
    end
  end

  defp fetch_api_key(opts) do
    case Config.firebase_api_key(opts) do
      api_key when is_binary(api_key) and api_key != "" -> {:ok, api_key}
      _ -> {:error, :missing_api_key}
    end
  end

  defp normalize_email(email) do
    normalized = String.trim(email)

    if normalized == "" do
      {:error, :invalid_email}
    else
      {:ok, normalized}
    end
  end

  defp normalize_continue_url(continue_url) do
    normalized = String.trim(continue_url)

    if normalized == "" do
      {:error, :invalid_continue_url}
    else
      {:ok, normalized}
    end
  end

  defp base_url(opts) do
    Keyword.get(opts, :identity_toolkit_base_url, @identitytoolkit_base)
  end

  defp compact_map(map) do
    Enum.reduce(map, %{}, fn
      {_key, nil}, acc -> acc
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end

  defp blank_to_nil(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp blank_to_nil(_value), do: nil
end
