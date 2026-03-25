defmodule Fireauth.ServerAuth.SignInResult do
  @moduledoc """
  Result returned by `accounts.signInWithIdp`.
  """

  @type t :: %__MODULE__{
          provider_id: String.t() | nil,
          federated_id: String.t() | nil,
          local_id: String.t() | nil,
          email: String.t() | nil,
          email_verified: boolean() | nil,
          display_name: String.t() | nil,
          photo_url: String.t() | nil,
          firebase_id_token: String.t() | nil,
          refresh_token: String.t() | nil,
          expires_in: integer() | nil,
          is_new_user: boolean() | nil,
          need_confirmation: boolean() | nil,
          pending_token: String.t() | nil,
          oauth_access_token: String.t() | nil,
          oauth_refresh_token: String.t() | nil,
          oauth_authorization_code: String.t() | nil,
          raw_response: map()
        }

  defstruct [
    :provider_id,
    :federated_id,
    :local_id,
    :email,
    :email_verified,
    :display_name,
    :photo_url,
    :firebase_id_token,
    :refresh_token,
    :expires_in,
    :is_new_user,
    :need_confirmation,
    :pending_token,
    :oauth_access_token,
    :oauth_refresh_token,
    :oauth_authorization_code,
    :raw_response
  ]
end
