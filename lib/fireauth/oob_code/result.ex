defmodule Fireauth.OobCode.Result do
  @moduledoc false

  @enforce_keys [:raw_response]
  defstruct [:operation, :email, :new_email, :raw_response]

  @type operation ::
          :verify_email
          | :password_reset
          | :recover_email
          | :verify_and_change_email
          | :email_signin
          | {:unknown, String.t()}

  @type t :: %__MODULE__{
          operation: operation() | nil,
          email: String.t() | nil,
          new_email: String.t() | nil,
          raw_response: map()
        }
end
