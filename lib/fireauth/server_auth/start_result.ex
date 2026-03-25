defmodule Fireauth.ServerAuth.StartResult do
  @moduledoc """
  Provider redirect data returned by `accounts.createAuthUri`.
  """

  @type t :: %__MODULE__{
          provider_id: String.t() | nil,
          auth_uri: String.t(),
          session_id: String.t(),
          context: String.t() | nil,
          raw_response: map()
        }

  defstruct [:provider_id, :auth_uri, :session_id, :context, :raw_response]
end
