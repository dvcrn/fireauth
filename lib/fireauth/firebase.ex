defmodule Fireauth.Firebase do
  @moduledoc """
  Firebase claim helpers.

  Token verification is handled by `Fireauth.TokenValidator` (default:
  `Fireauth.FirebaseTokenValidator`).
  """

  alias Fireauth.Claims
  alias Fireauth.TokenValidator
  alias Fireauth.User

  @type id_token :: String.t()

  @typedoc """
  Verified Firebase ID token claims.
  """
  @type firebase_claims :: Claims.t()

  @typedoc """
  Attributes derived from Firebase claims.
  """
  @type user_attrs :: User.t()

  @doc """
  Verify a Firebase ID token and return its claims.

  Delegates to `Fireauth.TokenValidator` (adapter pattern).
  """
  @spec verify_id_token(id_token(), keyword()) :: {:ok, firebase_claims()} | {:error, term()}
  def verify_id_token(token, opts \\ []) when is_binary(token) and is_list(opts) do
    TokenValidator.verify_id_token(token, opts)
  end

  # No token verification internals here. See `Fireauth.FirebaseTokenValidator`.
end
