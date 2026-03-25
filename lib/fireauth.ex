defmodule Fireauth do
  @moduledoc """
  Fireauth is a small library for Firebase Auth integration:

  - `Fireauth.verify_id_token/2` verifies Firebase SecureToken ID tokens.
  - `Fireauth.create_session_cookie/2` mints Firebase session cookies (requires admin service account).
  - `Fireauth.Plug` optionally attaches verified claims to `conn.assigns`
    and serves Firebase hosted auth helper files at `/__/auth/*` via proxy,
    static files, or callback overrides.
  """

  alias Fireauth.{Claims, TokenValidator}
  alias Fireauth.EmailLinkSender.Result, as: EmailLinkResult
  alias Fireauth.ServerAuth.{SignInResult, StartResult}

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
    Fireauth.SessionCookieCreator.create_session_cookie(id_token, opts)
  end

  @doc """
  Build a provider redirect URI for a server-owned OAuth sign-in flow.
  """
  @spec start_oauth_sign_in(String.t(), String.t(), keyword()) ::
          {:ok, StartResult.t()} | {:error, term()}
  def start_oauth_sign_in(provider_id, callback_uri, opts \\ [])
      when is_binary(provider_id) and is_binary(callback_uri) and is_list(opts) do
    Fireauth.ServerAuth.start_oauth_sign_in(provider_id, callback_uri, opts)
  end

  @doc """
  Finish an OAuth provider callback and return a Firebase ID token.
  """
  @spec finish_oauth_sign_in(String.t(), String.t(), String.t() | nil, keyword()) ::
          {:ok, SignInResult.t()} | {:error, term()}
  def finish_oauth_sign_in(request_uri, session_id, post_body \\ nil, opts \\ [])
      when is_binary(request_uri) and is_binary(session_id) and is_list(opts) do
    Fireauth.ServerAuth.finish_oauth_sign_in(request_uri, session_id, post_body, opts)
  end

  @doc """
  Send an email-link sign-in action through Firebase Identity Toolkit.
  """
  @spec send_email_sign_in_link(String.t(), String.t(), keyword()) ::
          {:ok, EmailLinkResult.t()} | {:error, term()}
  def send_email_sign_in_link(email, continue_url, opts \\ [])
      when is_binary(email) and is_binary(continue_url) and is_list(opts) do
    Fireauth.EmailLinkSender.send_sign_in_link(email, continue_url, opts)
  end

  @doc """
  Mint a Firebase custom token for the given UID.

  The token is a short-lived JWT (1 hour) signed with the service account
  private key. Pass it to the client-side Firebase SDK via
  `signInWithCustomToken` to establish a client-side session.

  ## Options

    * `:otp_app` - the OTP app to read config from (default `:fireauth`)
    * `:claims` - optional map of additional claims (max 1000 bytes)
  """
  @spec create_custom_token(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def create_custom_token(uid, opts \\ []) when is_binary(uid) and is_list(opts) do
    Fireauth.CustomToken.create_custom_token(uid, opts)
  end

  @doc """
  Unlink a provider from a Firebase user.

  Calls Identity Toolkit `accounts:update` with `deleteProvider`. Requires
  an ID token for the user whose provider should be removed.
  """
  @spec unlink_provider(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def unlink_provider(id_token, provider_id, opts \\ [])
      when is_binary(id_token) and is_binary(provider_id) and is_list(opts) do
    Fireauth.Account.unlink_provider(id_token, provider_id, opts)
  end

  @doc """
  Exchange a custom token for a Firebase ID token.

  Makes a REST API call to `accounts:signInWithCustomToken`. Useful for
  server-side flows that need an ID token for the current user, e.g. to pass
  as the `:id_token` option to `finish_oauth_sign_in/4` for provider linking.
  """
  @spec exchange_custom_token(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def exchange_custom_token(custom_token, opts \\ [])
      when is_binary(custom_token) and is_list(opts) do
    Fireauth.CustomToken.exchange_custom_token(custom_token, opts)
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
