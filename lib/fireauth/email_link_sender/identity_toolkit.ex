defmodule Fireauth.EmailLinkSender.IdentityToolkit do
  @moduledoc false

  @behaviour Fireauth.EmailLinkSender

  alias Fireauth.EmailLinkSender.Result
  alias Fireauth.IdentityToolkit.Client

  @impl true
  @spec send_sign_in_link(String.t(), String.t(), keyword()) ::
          {:ok, Result.t()} | {:error, term()}
  def send_sign_in_link(email, continue_url, opts)
      when is_binary(email) and is_binary(continue_url) and is_list(opts) do
    with {:ok, normalized_email} <- normalize_email(email),
         {:ok, normalized_continue_url} <- normalize_continue_url(continue_url),
         {:ok, api_key} <- Client.fetch_api_key(opts),
         {:ok, %{} = response} <-
           Client.post(
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
      "dynamicLinkDomain" => Client.blank_to_nil(Keyword.get(opts, :dynamic_link_domain)),
      "iOSBundleId" => Client.blank_to_nil(Keyword.get(opts, :ios_bundle_id)),
      "androidPackageName" => Client.blank_to_nil(Keyword.get(opts, :android_package_name)),
      "androidInstallApp" => Keyword.get(opts, :android_install_app),
      "androidMinimumVersion" => Client.blank_to_nil(Keyword.get(opts, :android_minimum_version)),
      "tenantId" => Client.blank_to_nil(Keyword.get(opts, :tenant_id))
    }
    |> Client.compact_map()
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
end
