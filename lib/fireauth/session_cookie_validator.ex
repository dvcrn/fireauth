defmodule Fireauth.SessionCookieValidator do
  @moduledoc """
  Session cookie validator adapter interface.

  This follows the same adapter pattern as `Fireauth.TokenValidator`:

  - Call `Fireauth.SessionCookieValidator.verify_session_cookie/2`
  - It delegates to the configured adapter module.

  Configure via:

  ```elixir
  config :fireauth, :session_cookie_validator_adapter, Fireauth.SessionCookieValidator.Firebase
  ```
  """

  @type session_cookie :: String.t()
  @type claims :: Fireauth.Claims.t()
  @type opts :: keyword()

  @callback verify_session_cookie(session_cookie(), opts()) :: {:ok, claims()} | {:error, term()}

  @spec verify_session_cookie(session_cookie(), opts()) :: {:ok, claims()} | {:error, term()}
  def verify_session_cookie(cookie, opts \\ []) when is_binary(cookie) and is_list(opts) do
    adapter().verify_session_cookie(cookie, opts)
  end

  defp adapter do
    Application.get_env(
      :fireauth,
      :session_cookie_validator_adapter,
      Fireauth.SessionCookieValidator.Firebase
    )
  end
end
