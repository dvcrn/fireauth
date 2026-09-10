defmodule Fireauth.PasswordReset do
  @moduledoc """
  Send and complete Firebase password resets from the server.

  `send_email/3` asks Firebase to mail a reset link; the `oobCode` on that link
  comes back to your action handler, where `confirm/3` exchanges it for a new
  password. `Fireauth.OobCode.check/2` reports the address a code belongs to
  without spending it, which is what lets a reset form name the account it is
  about.
  """

  alias Fireauth.PasswordReset.Result

  @type email :: String.t()
  @type continue_url :: String.t()
  @type oob_code :: String.t()
  @type new_password :: String.t()
  @type opts :: keyword()

  @callback send_email(email(), continue_url() | nil, opts()) ::
              {:ok, Result.t()} | {:error, term()}
  @callback confirm(oob_code(), new_password(), opts()) :: {:ok, Result.t()} | {:error, term()}

  @doc """
  Mail a password reset link to the given address.

  `continue_url` is where Firebase's action page sends the user afterwards; pass
  `nil` to leave it out.
  """
  @spec send_email(email(), continue_url() | nil, opts()) :: {:ok, Result.t()} | {:error, term()}
  def send_email(email, continue_url \\ nil, opts \\ [])
      when is_binary(email) and (is_binary(continue_url) or is_nil(continue_url)) and
             is_list(opts) do
    adapter().send_email(email, continue_url, opts)
  end

  @doc """
  Set a new password using the `oobCode` from a reset email.
  """
  @spec confirm(oob_code(), new_password(), opts()) :: {:ok, Result.t()} | {:error, term()}
  def confirm(oob_code, new_password, opts \\ [])
      when is_binary(oob_code) and is_binary(new_password) and is_list(opts) do
    adapter().confirm(oob_code, new_password, opts)
  end

  defp adapter do
    Application.get_env(
      :fireauth,
      :password_reset_adapter,
      Fireauth.PasswordReset.IdentityToolkit
    )
  end
end
