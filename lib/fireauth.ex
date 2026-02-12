defmodule Fireauth do
  @moduledoc """
  Fireauth is a small library for Firebase Auth integration:

  - `Fireauth.verify_id_token/2` verifies Firebase SecureToken ID tokens.
  - `Fireauth.create_session_cookie/2` mints Firebase session cookies (requires admin service account).
  - `Fireauth.Plug` optionally attaches verified claims to `conn.assigns`
    and proxies Firebase hosted auth helper files at `/__/auth/*`.
  """

  alias Fireauth.{Claims, TokenValidator}

  @type id_token :: String.t()
  @type claims :: Claims.t()

  defstruct [:user, :claims, :token]

  @type t :: %__MODULE__{
          user: Fireauth.User.t() | nil,
          claims: Fireauth.Claims.t() | nil,
          token: String.t() | nil
        }

  @doc """
  Verify a Firebase ID token and return its claims.

  Delegates to `Fireauth.TokenValidator` (adapter pattern).
  """
  @spec verify_id_token(id_token(), keyword()) :: {:ok, claims()} | {:error, term()}
  def verify_id_token(token, opts \\ []) when is_binary(token) and is_list(opts) do
    TokenValidator.verify_id_token(token, opts)
  end

  @doc """
  Verify a Firebase session cookie and return its claims.
  """
  @spec verify_session_cookie(String.t(), keyword()) :: {:ok, claims()} | {:error, term()}
  def verify_session_cookie(cookie, opts \\ []) when is_binary(cookie) and is_list(opts) do
    Fireauth.SessionCookieValidator.verify_session_cookie(cookie, opts)
  end

  @doc """
  Exchange an ID token for a Firebase session cookie.

  This makes a network call to Google (Identity Toolkit
  `projects.createSessionCookie`). It requires a Firebase Admin service account
  (OAuth).
  """
  @spec create_session_cookie(id_token(), keyword()) ::
          {:ok, Fireauth.SessionCookie.session_cookie()} | {:error, term()}
  def create_session_cookie(id_token, opts \\ []) when is_binary(id_token) and is_list(opts) do
    Fireauth.SessionCookie.exchange_id_token(id_token, opts)
  end

  @doc """
  Convert verified Firebase claims into the common user attrs map.
  """
  @spec claims_to_user_attrs(claims()) :: Fireauth.User.t()
  def claims_to_user_attrs(%Claims{} = claims), do: Fireauth.User.from_claims(claims)

  @doc """
  Get all identities from a user, claims, or Fireauth struct.
  """
  @spec identities(Fireauth.User.t() | Fireauth.Claims.t() | t()) :: map()
  def identities(%Fireauth{user: user}), do: identities(user)

  def identities(%{identities: identities}) when is_map(identities), do: identities

  def identities(_data), do: %{}

  @doc """
  Check if the given user, claims, or Fireauth struct has an identity for the specified provider.
  """
  @spec has_identity?(Fireauth.User.t() | Fireauth.Claims.t() | t(), String.t() | atom()) ::
          boolean()
  def has_identity?(%Fireauth{user: user}, provider), do: has_identity?(user, provider)

  def has_identity?(%{identities: identities}, provider) when is_map(identities) do
    Map.has_key?(identities, to_string(provider))
  end

  def has_identity?(_data, _provider), do: false

  @doc """
  Get the first identity ID for the given provider from a user, claims, or Fireauth struct.
  """
  @spec identity(Fireauth.User.t() | Fireauth.Claims.t() | t(), String.t() | atom()) ::
          String.t() | nil
  def identity(%Fireauth{user: user}, provider), do: identity(user, provider)

  def identity(%{identities: identities}, provider) when is_map(identities) do
    case Map.get(identities, to_string(provider)) do
      [id | _] -> id
      _ -> nil
    end
  end

  def identity(_data, _provider), do: nil
end
