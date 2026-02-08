defmodule Fireauth.Claims do
  @moduledoc """
  Structured representation of Firebase ID Token claims.
  """

  @type t :: %__MODULE__{
          sub: String.t(),
          iss: String.t(),
          aud: String.t(),
          exp: integer(),
          iat: integer(),
          auth_time: integer(),
          user_id: String.t(),
          email: String.t() | nil,
          email_verified: boolean() | nil,
          name: String.t() | nil,
          picture: String.t() | nil,
          sign_in_provider: String.t() | nil,
          identities: map() | nil,
          raw_claims: map()
        }

  defstruct [
    :sub,
    :iss,
    :aud,
    :exp,
    :iat,
    :auth_time,
    :user_id,
    :email,
    :email_verified,
    :name,
    :picture,
    :sign_in_provider,
    :identities,
    :raw_claims
  ]

  @doc """
  Creates a new `Fireauth.Claims` struct from a raw JWT claims map.
  """
  @spec new(map()) :: t()
  def new(claims) when is_map(claims) do
    firebase = Map.get(claims, "firebase") || %{}

    %__MODULE__{
      sub: claims["sub"],
      iss: claims["iss"],
      aud: claims["aud"],
      exp: claims["exp"],
      iat: claims["iat"],
      auth_time: claims["auth_time"],
      user_id: claims["user_id"] || claims["sub"],
      email: claims["email"],
      email_verified: claims["email_verified"],
      name: claims["name"],
      picture: claims["picture"],
      sign_in_provider: Map.get(firebase, "sign_in_provider"),
      identities: Map.get(firebase, "identities"),
      raw_claims: claims
    }
  end
end
