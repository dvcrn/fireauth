defmodule Fireauth.PasswordReset.Result do
  @moduledoc false

  @enforce_keys [:raw_response]
  defstruct [:email, :raw_response]

  @type t :: %__MODULE__{
          email: String.t() | nil,
          raw_response: map()
        }
end
