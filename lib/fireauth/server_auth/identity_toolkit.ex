defmodule Fireauth.ServerAuth.IdentityToolkit do
  @moduledoc false

  @behaviour Fireauth.ServerAuth

  alias Fireauth.Admin.OAuth
  alias Fireauth.Config
  alias Fireauth.ServerAuth.{SignInResult, StartResult}

  @identitytoolkit_base "https://identitytoolkit.googleapis.com/v1"
  @google_scope "openid email profile"

  @impl true
  @spec start_oauth_sign_in(String.t(), String.t(), keyword()) ::
          {:ok, StartResult.t()} | {:error, term()}
  def start_oauth_sign_in(provider_id, callback_uri, opts)
      when is_binary(provider_id) and is_binary(callback_uri) and is_list(opts) do
    with {:ok, api_key} <- fetch_api_key(opts),
         {:ok, body} <- build_start_body(provider_id, callback_uri, opts),
         {:ok, %{"authUri" => auth_uri, "sessionId" => session_id} = response} <-
           post("accounts:createAuthUri", api_key, body, opts) do
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
    with {:ok, api_key} <- fetch_api_key(opts),
         {:ok, response} <-
           post(
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
    if blank?(provider_id) or blank?(callback_uri) do
      {:error, :invalid_oauth_request}
    else
      provider_defaults = provider_defaults(provider_id)

      body =
        %{
          "providerId" => provider_id,
          "continueUri" => callback_uri,
          "sessionId" => blank_to_nil(Keyword.get(opts, :session_id)),
          "context" => blank_to_nil(Keyword.get(opts, :context)),
          "oauthScope" =>
            blank_to_nil(Keyword.get(opts, :oauth_scope, provider_defaults[:oauth_scope])),
          "authFlowType" =>
            blank_to_nil(Keyword.get(opts, :auth_flow_type, provider_defaults[:auth_flow_type])),
          "hostedDomain" => blank_to_nil(Keyword.get(opts, :hosted_domain)),
          "customParameter" =>
            normalize_custom_parameters(
              Keyword.get(opts, :custom_parameters, provider_defaults[:custom_parameters])
            ),
          "tenantId" => blank_to_nil(Keyword.get(opts, :tenant_id))
        }
        |> compact_map()

      {:ok, body}
    end
  end

  defp build_finish_body(request_uri, session_id, post_body, opts) do
    %{
      "requestUri" => request_uri,
      "sessionId" => session_id,
      "postBody" => blank_to_nil(post_body),
      "returnSecureToken" => true,
      "returnIdpCredential" => true,
      "tenantId" => blank_to_nil(Keyword.get(opts, :tenant_id))
    }
    |> compact_map()
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

  defp fetch_api_key(opts) do
    case Config.firebase_api_key(opts) do
      api_key when is_binary(api_key) and api_key != "" -> {:ok, api_key}
      _ -> {:error, :missing_api_key}
    end
  end

  defp base_url(opts) do
    Keyword.get(opts, :identity_toolkit_base_url, @identitytoolkit_base)
  end

  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp parse_integer(_value), do: nil

  defp compact_map(map) do
    Enum.reduce(map, %{}, fn
      {_key, nil}, acc -> acc
      {_key, value}, acc when is_map(value) and map_size(value) == 0 -> acc
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end

  defp normalize_custom_parameters(nil), do: nil
  defp normalize_custom_parameters(%{} = custom_parameters), do: custom_parameters
  defp normalize_custom_parameters(_other), do: nil

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""

  defp blank_to_nil(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp blank_to_nil(_value), do: nil
end
