defmodule Fireauth.CustomToken.Firebase do
  @moduledoc false

  @behaviour Fireauth.CustomToken

  alias Fireauth.Admin.ServiceAccount
  alias Fireauth.Config
  alias Fireauth.IdentityToolkit.Client

  @audience "https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit"
  @max_uid_length 128
  @token_lifetime_s 3600

  @impl true
  @spec create_custom_token(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def create_custom_token(uid, opts \\ []) when is_binary(uid) and is_list(opts) do
    with :ok <- validate_uid(uid),
         {:ok, sa} <- fetch_service_account(opts),
         {:ok, client_email} <- ServiceAccount.fetch_required(sa, "client_email"),
         {:ok, private_key_pem} <- ServiceAccount.fetch_required(sa, "private_key") do
      sign_token(uid, client_email, private_key_pem, Keyword.get(opts, :claims))
    end
  end

  @impl true
  @spec exchange_custom_token(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def exchange_custom_token(custom_token, opts \\ [])
      when is_binary(custom_token) and is_list(opts) do
    with {:ok, api_key} <- Client.fetch_api_key(opts),
         {:ok, %{"idToken" => id_token}} <-
           Client.post(
             "accounts:signInWithCustomToken",
             api_key,
             %{"token" => custom_token, "returnSecureToken" => true},
             opts
           ) do
      {:ok, id_token}
    end
  end

  @spec validate_uid(String.t()) :: :ok | {:error, :invalid_uid}
  defp validate_uid(uid) do
    if uid != "" and byte_size(uid) <= @max_uid_length do
      :ok
    else
      {:error, :invalid_uid}
    end
  end

  @spec fetch_service_account(keyword()) :: {:ok, ServiceAccount.t()} | {:error, term()}
  defp fetch_service_account(opts) do
    case Config.firebase_admin_service_account(opts) do
      %{} = sa -> {:ok, sa}
      nil -> {:error, :missing_service_account}
    end
  end

  @spec sign_token(String.t(), String.t(), String.t(), map() | nil) ::
          {:ok, String.t()} | {:error, term()}
  defp sign_token(uid, client_email, private_key_pem, additional_claims) do
    now = System.system_time(:second)

    payload =
      %{
        "iss" => client_email,
        "sub" => client_email,
        "aud" => @audience,
        "iat" => now,
        "exp" => now + @token_lifetime_s,
        "uid" => uid
      }
      |> maybe_add_claims(additional_claims)

    jwk = JOSE.JWK.from_pem(private_key_pem)

    {_, jwt} =
      JOSE.JWT.sign(jwk, %{"alg" => "RS256", "typ" => "JWT"}, payload)
      |> JOSE.JWS.compact()

    {:ok, jwt}
  rescue
    e in [ArgumentError, ErlangError] -> {:error, {:exception, e}}
  catch
    :exit, reason -> {:error, {:exit, reason}}
  end

  @spec maybe_add_claims(map(), map() | nil) :: map()
  defp maybe_add_claims(payload, nil), do: payload
  defp maybe_add_claims(payload, claims) when claims == %{}, do: payload
  defp maybe_add_claims(payload, claims) when is_map(claims), do: Map.put(payload, "claims", claims)
end
