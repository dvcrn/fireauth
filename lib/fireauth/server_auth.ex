defmodule Fireauth.ServerAuth do
  @moduledoc """
  Server-owned OAuth sign-in flow for Firebase / Identity Platform.

  The public API is intentionally small:

  - `start_oauth_sign_in/3` returns the provider redirect URL
  - `finish_oauth_sign_in/4` exchanges the provider callback for a Firebase ID token
  """

  alias Fireauth.ServerAuth.{SignInResult, StartResult}

  @type provider_id :: String.t()
  @type callback_uri :: String.t()
  @type request_uri :: String.t()
  @type post_body :: String.t() | nil
  @type opts :: keyword()

  @callback start_oauth_sign_in(provider_id(), callback_uri(), opts()) ::
              {:ok, StartResult.t()} | {:error, term()}

  @callback finish_oauth_sign_in(request_uri(), String.t(), post_body(), opts()) ::
              {:ok, SignInResult.t()} | {:error, term()}

  @doc """
  Build the upstream authorization URI for a provider sign-in.
  """
  @spec start_oauth_sign_in(provider_id(), callback_uri(), opts()) ::
          {:ok, StartResult.t()} | {:error, term()}
  def start_oauth_sign_in(provider_id, callback_uri, opts \\ [])
      when is_binary(provider_id) and is_binary(callback_uri) and is_list(opts) do
    adapter().start_oauth_sign_in(provider_id, callback_uri, opts)
  end

  @doc """
  Finish a provider callback and exchange it for a Firebase ID token.
  """
  @spec finish_oauth_sign_in(request_uri(), String.t(), post_body(), opts()) ::
          {:ok, SignInResult.t()} | {:error, term()}
  def finish_oauth_sign_in(request_uri, session_id, post_body \\ nil, opts \\ [])
      when is_binary(request_uri) and is_binary(session_id) and is_list(opts) do
    adapter().finish_oauth_sign_in(request_uri, session_id, post_body, opts)
  end

  defp adapter do
    Application.get_env(
      :fireauth,
      :server_auth_adapter,
      Fireauth.ServerAuth.IdentityToolkit
    )
  end
end
