defmodule Fireauth do
  @moduledoc """
  Fireauth is a small library for Firebase Auth integration:

  - `Fireauth.verify_id_token/2` verifies Firebase SecureToken ID tokens.
  - `Fireauth.Plug` optionally attaches verified claims to `conn.assigns`
    and proxies Firebase hosted auth helper files at `/__/auth/*`.
  """

  alias Fireauth.{Claims, TokenValidator}

  @type id_token :: String.t()
  @type claims :: Claims.t()

  @doc """
  Verify a Firebase ID token and return its claims.

  Delegates to `Fireauth.TokenValidator` (adapter pattern).
  """
  @spec verify_id_token(id_token(), keyword()) :: {:ok, claims()} | {:error, term()}
  def verify_id_token(token, opts \\ []) when is_binary(token) and is_list(opts) do
    TokenValidator.verify_id_token(token, opts)
  end

  @doc """
  Convert verified Firebase claims into the common user attrs map.
  """
  @spec claims_to_user_attrs(claims()) :: Fireauth.User.t()
  def claims_to_user_attrs(%Claims{} = claims), do: Fireauth.User.from_claims(claims)

  @doc """
  Check if the given user or claims has an identity for the specified provider.
  """
  @spec has_identity?(Fireauth.User.t() | Fireauth.Claims.t(), String.t() | atom()) :: boolean()
  def has_identity?(%{identities: identities}, provider) when is_map(identities) do
    Map.has_key?(identities, to_string(provider))
  end

  def has_identity?(_data, _provider), do: false

  @doc """
  Get the first identity ID for the given provider from a user or claims.
  """
  @spec identity(Fireauth.User.t() | Fireauth.Claims.t(), String.t() | atom()) ::
          String.t() | nil
  def identity(%{identities: identities}, provider) when is_map(identities) do
    case Map.get(identities, to_string(provider)) do
      [id | _] -> id
      _ -> nil
    end
  end

  def identity(_data, _provider), do: nil
end
