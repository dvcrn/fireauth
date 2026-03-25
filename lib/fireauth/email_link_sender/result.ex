defmodule Fireauth.EmailLinkSender.Result do
  @moduledoc false

  @enforce_keys [:email, :raw_response]
  defstruct [:email, :raw_response]

  @type t :: %__MODULE__{
          email: String.t(),
          raw_response: map()
        }
end
