defmodule Fireauth do
  @moduledoc """
  Fireauth is a small library for Firebase Auth integration:

  - `Fireauth.verify_id_token/2` verifies Firebase SecureToken ID tokens.
  - `Fireauth.Plug` optionally attaches verified claims to `conn.assigns`
    and proxies Firebase hosted auth helper files at `/__/auth/*`.
  """

  alias Fireauth.{Firebase, TokenValidator}

  @type id_token :: String.t()
  @type claims :: %{optional(String.t()) => term()}

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
  @spec claims_to_user_attrs(claims()) :: map()
  def claims_to_user_attrs(%{} = claims), do: Firebase.claims_to_user_attrs(claims)
end
