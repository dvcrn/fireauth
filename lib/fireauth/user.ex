defmodule Fireauth.User do
  @moduledoc """
  Structured representation of a Firebase User derived from ID Token claims.
  """

  @type provider_identity_map :: %{optional(String.t()) => [String.t()]}

  @type t :: %__MODULE__{
          firebase_uid: String.t(),
          email: String.t() | nil,
          name: String.t() | nil,
          avatar_url: String.t() | nil,
          email_verified: boolean() | nil,
          sign_in_provider: String.t() | nil,
          identities: provider_identity_map() | nil
        }

  defstruct [
    :firebase_uid,
    :email,
    :name,
    :avatar_url,
    :email_verified,
    :sign_in_provider,
    :identities
  ]

  @doc """
  Builds a `%Fireauth.User{}` from a `%Fireauth.Claims{}` struct.
  """
  @spec from_claims(Fireauth.Claims.t()) :: t()
  def from_claims(%Fireauth.Claims{} = claims) do
    identities = claims.identities || %{}

    %__MODULE__{
      firebase_uid: claims.user_id,
      email: claims.email,
      name: claims.name,
      avatar_url: claims.picture,
      email_verified: claims.email_verified,
      sign_in_provider: claims.sign_in_provider,
      identities: if(map_size(identities) == 0, do: nil, else: identities)
    }
  end
end
