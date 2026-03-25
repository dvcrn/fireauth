defmodule Fireauth.ServerAuth.IdentityToolkit do
  @moduledoc false

  @behaviour Fireauth.ServerAuth

  alias Fireauth.IdentityToolkit.Client
  alias Fireauth.ServerAuth.{SignInResult, StartResult}

  @google_scope "openid email profile"

  @impl true
  @spec start_oauth_sign_in(String.t(), String.t(), keyword()) ::
          {:ok, StartResult.t()} | {:error, term()}
  def start_oauth_sign_in(provider_id, callback_uri, opts)
      when is_binary(provider_id) and is_binary(callback_uri) and is_list(opts) do
    with {:ok, api_key} <- Client.fetch_api_key(opts),
         {:ok, body} <- build_start_body(provider_id, callback_uri, opts),
         {:ok, %{"authUri" => auth_uri, "sessionId" => session_id} = response} <-
           Client.post("accounts:createAuthUri", api_key, body, opts) do
      {:ok,
       %StartResult{
         provider_id: response["providerId"] || provider_id,
         auth_uri: auth_uri,
         session_id: session_id,
         context: response["context"],
         raw_response: response
       }}
    else
      {:ok, response} ->
        {:error, {:invalid_create_auth_uri_response, response}}

      {:error, _reason} = error ->
        error
    end
  end

  @impl true
  @spec finish_oauth_sign_in(String.t(), String.t(), String.t() | nil, keyword()) ::
          {:ok, SignInResult.t()} | {:error, term()}
  def finish_oauth_sign_in(request_uri, session_id, post_body, opts)
      when is_binary(request_uri) and is_binary(session_id) and is_list(opts) do
    with {:ok, api_key} <- Client.fetch_api_key(opts),
         {:ok, response} <-
           Client.post(
             "accounts:signInWithIdp",
             api_key,
             build_finish_body(request_uri, session_id, post_body, opts),
             opts
           ) do
      response
      |> sign_in_result()
      |> validate_sign_in_result(response)
    end
  end

  defp build_start_body(provider_id, callback_uri, opts) do
    if Client.blank?(provider_id) or Client.blank?(callback_uri) do
      {:error, :invalid_oauth_request}
    else
      provider_defaults = provider_defaults(provider_id)

      body =
        %{
          "providerId" => provider_id,
          "continueUri" => callback_uri,
          "sessionId" => Client.blank_to_nil(Keyword.get(opts, :session_id)),
          "context" => Client.blank_to_nil(Keyword.get(opts, :context)),
          "oauthScope" =>
            Client.blank_to_nil(Keyword.get(opts, :oauth_scope, provider_defaults[:oauth_scope])),
          "authFlowType" =>
            Client.blank_to_nil(
              Keyword.get(opts, :auth_flow_type, provider_defaults[:auth_flow_type])
            ),
          "hostedDomain" => Client.blank_to_nil(Keyword.get(opts, :hosted_domain)),
          "customParameter" =>
            normalize_custom_parameters(
              Keyword.get(opts, :custom_parameters, provider_defaults[:custom_parameters])
            ),
          "tenantId" => Client.blank_to_nil(Keyword.get(opts, :tenant_id))
        }
        |> Client.compact_map()

      {:ok, body}
    end
  end

  defp build_finish_body(request_uri, session_id, post_body, opts) do
    %{
      "requestUri" => request_uri,
      "sessionId" => session_id,
      "postBody" => Client.blank_to_nil(post_body),
      "returnSecureToken" => true,
      "returnIdpCredential" => true,
      "tenantId" => Client.blank_to_nil(Keyword.get(opts, :tenant_id))
    }
    |> Client.compact_map()
  end

  defp provider_defaults("google.com") do
    [
      oauth_scope: @google_scope,
      auth_flow_type: "CODE_FLOW",
      custom_parameters: %{"prompt" => "select_account"}
    ]
  end

  defp provider_defaults(_provider_id), do: []

  defp sign_in_result(response) do
    %SignInResult{
      provider_id: response["providerId"],
      federated_id: response["federatedId"],
      local_id: response["localId"],
      email: response["email"],
      email_verified: response["emailVerified"],
      display_name: response["displayName"] || response["fullName"],
      photo_url: response["photoUrl"],
      firebase_id_token: response["idToken"],
      refresh_token: response["refreshToken"],
      expires_in: parse_integer(response["expiresIn"]),
      is_new_user: response["isNewUser"],
      need_confirmation: response["needConfirmation"],
      pending_token: response["pendingToken"],
      oauth_access_token: response["oauthAccessToken"],
      oauth_refresh_token: response["oauthRefreshToken"],
      oauth_authorization_code: response["oauthAuthorizationCode"],
      raw_response: response
    }
  end

  defp validate_sign_in_result(%SignInResult{need_confirmation: true} = result, _response) do
    {:error, {:need_confirmation, result}}
  end

  defp validate_sign_in_result(
         %SignInResult{pending_token: pending_token, firebase_id_token: firebase_id_token} =
           result,
         _response
       )
       when is_binary(pending_token) and pending_token != "" and not is_binary(firebase_id_token) do
    {:error, {:pending_token, result}}
  end

  defp validate_sign_in_result(
         %SignInResult{firebase_id_token: firebase_id_token} = result,
         _response
       )
       when is_binary(firebase_id_token) and firebase_id_token != "" do
    {:ok, result}
  end

  defp validate_sign_in_result(_result, response), do: {:error, {:missing_id_token, response}}

  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp parse_integer(_value), do: nil

  defp normalize_custom_parameters(nil), do: nil
  defp normalize_custom_parameters(%{} = custom_parameters), do: custom_parameters
  defp normalize_custom_parameters(_other), do: nil
end
