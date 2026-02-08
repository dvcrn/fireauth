defmodule Fireauth.TokenValidator do
  @moduledoc """
  Token validator adapter interface.

  This follows the same adapter pattern as `RevenueCat.Client`:

  - Call `Fireauth.TokenValidator.verify_id_token/2`
  - It delegates to the configured adapter module.

  Configure via:

  ```elixir
  config :fireauth, :token_validator_adapter, Fireauth.TokenValidator.Firebase
  ```
  """

  @type id_token :: String.t()
  @type claims :: Fireauth.Claims.t()
  @type opts :: keyword()

  @callback verify_id_token(id_token(), opts()) :: {:ok, claims()} | {:error, term()}

  @spec verify_id_token(id_token(), opts()) :: {:ok, claims()} | {:error, term()}
  def verify_id_token(token, opts \\ []) when is_binary(token) and is_list(opts) do
    adapter().verify_id_token(token, opts)
  end

  defp adapter do
    Application.get_env(:fireauth, :token_validator_adapter, Fireauth.TokenValidator.Firebase)
  end
end
