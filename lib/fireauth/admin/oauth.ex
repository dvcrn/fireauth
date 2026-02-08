defmodule Fireauth.Admin.OAuth do
  @moduledoc false

  alias Fireauth.Admin.ServiceAccount

  @default_token_uri "https://oauth2.googleapis.com/token"
  @default_scope "https://www.googleapis.com/auth/identitytoolkit"

  @spec fetch_access_token(ServiceAccount.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def fetch_access_token(%{} = sa, opts \\ []) when is_list(opts) do
    scope = Keyword.get(opts, :scope, @default_scope)

    with {:ok, client_email} <- ServiceAccount.fetch_required(sa, "client_email"),
         {:ok, private_key_pem} <- ServiceAccount.fetch_required(sa, "private_key"),
         token_uri <- Map.get(sa, "token_uri") || @default_token_uri,
         {:ok, assertion} <- build_assertion(client_email, private_key_pem, token_uri, scope) do
      exchange_assertion_for_access_token(token_uri, assertion)
    end
  end

  @spec build_assertion(binary(), binary(), binary(), binary()) ::
          {:ok, binary()} | {:error, term()}
  def build_assertion(client_email, private_key_pem, token_uri, scope)
      when is_binary(client_email) and is_binary(private_key_pem) and is_binary(token_uri) and
             is_binary(scope) do
    now = System.system_time(:second)

    claims = %{
      "iss" => client_email,
      "sub" => client_email,
      "aud" => token_uri,
      "scope" => scope,
      "iat" => now,
      "exp" => now + 3600
    }

    jwk = JOSE.JWK.from_pem(private_key_pem)

    {_, jwt} =
      JOSE.JWT.sign(jwk, %{"alg" => "RS256", "typ" => "JWT"}, claims)
      |> JOSE.JWS.compact()

    {:ok, jwt}
  rescue
    e in [ArgumentError, ErlangError] -> {:error, {:exception, e}}
  catch
    :exit, reason -> {:error, {:exit, reason}}
  end

  defp exchange_assertion_for_access_token(token_uri, assertion)
       when is_binary(token_uri) and is_binary(assertion) do
    form = %{
      "grant_type" => "urn:ietf:params:oauth:grant-type:jwt-bearer",
      "assertion" => assertion
    }

    case Req.post(token_uri, form: form) do
      {:ok, %{status: 200, body: %{"access_token" => token}}}
      when is_binary(token) and token != "" ->
        {:ok, token}

      {:ok, %{status: status, body: body}} ->
        {:error, {:oauth_token_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
