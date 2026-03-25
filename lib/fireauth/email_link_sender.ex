defmodule Fireauth.EmailLinkSender do
  @moduledoc """
  Send Firebase email-link sign-in actions from the server.
  """

  alias Fireauth.EmailLinkSender.Result

  @type email :: String.t()
  @type continue_url :: String.t()
  @type opts :: keyword()

  @callback send_sign_in_link(email(), continue_url(), opts()) ::
              {:ok, Result.t()} | {:error, term()}

  @doc """
  Send an email-link sign-in action for the given email and continue URL.
  """
  @spec send_sign_in_link(email(), continue_url(), opts()) ::
          {:ok, Result.t()} | {:error, term()}
  def send_sign_in_link(email, continue_url, opts \\ [])
      when is_binary(email) and is_binary(continue_url) and is_list(opts) do
    adapter().send_sign_in_link(email, continue_url, opts)
  end

  defp adapter do
    Application.get_env(
      :fireauth,
      :email_link_sender_adapter,
      Fireauth.EmailLinkSender.IdentityToolkit
    )
  end
end
