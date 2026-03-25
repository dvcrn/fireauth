defmodule Fireauth.CustomToken do
  @moduledoc """
  Adapter interface for minting Firebase custom tokens.

  A custom token is a short-lived JWT signed with a service account private key.
  The client-side Firebase SDK can exchange it for a full Firebase session via
  `signInWithCustomToken`.
  """

  @type uid :: String.t()
  @type token :: String.t()
  @type opts :: keyword()

  @doc """
  Mint a Firebase custom token for the given UID.
  """
  @callback create_custom_token(uid(), opts()) :: {:ok, token()} | {:error, term()}

  @doc """
  Exchange a custom token for a Firebase ID token via the REST API.
  """
  @callback exchange_custom_token(token(), opts()) :: {:ok, String.t()} | {:error, term()}

  @doc """
  Mint a Firebase custom token for the given UID.

  The token is a short-lived JWT (1 hour) signed with the service account
  private key.
  """
  @spec create_custom_token(uid(), opts()) :: {:ok, token()} | {:error, term()}
  def create_custom_token(uid, opts \\ []) when is_binary(uid) and is_list(opts) do
    adapter().create_custom_token(uid, opts)
  end

  @doc """
  Exchange a custom token for a Firebase ID token via the REST API.

  This is useful for server-side flows that need an ID token for the current
  user (e.g. to pass to `finish_oauth_sign_in` for provider linking).
  """
  @spec exchange_custom_token(token(), opts()) :: {:ok, String.t()} | {:error, term()}
  def exchange_custom_token(token, opts \\ []) when is_binary(token) and is_list(opts) do
    adapter().exchange_custom_token(token, opts)
  end

  defp adapter do
    Application.get_env(
      :fireauth,
      :custom_token_adapter,
      Fireauth.CustomToken.Firebase
    )
  end
end
