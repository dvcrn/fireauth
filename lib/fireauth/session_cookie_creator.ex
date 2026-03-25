defmodule Fireauth.SessionCookieCreator do
  @moduledoc """
  Session cookie creator adapter interface.

  This keeps server-side session minting testable for callers that do not go
  through `Fireauth.Plug.SessionRouter`.
  """

  @type id_token :: String.t()
  @type session_cookie :: Fireauth.SessionCookie.session_cookie()
  @type opts :: keyword()

  @callback create_session_cookie(id_token(), opts()) ::
              {:ok, session_cookie()} | {:error, term()}

  @spec create_session_cookie(id_token(), opts()) :: {:ok, session_cookie()} | {:error, term()}
  def create_session_cookie(id_token, opts \\ []) when is_binary(id_token) and is_list(opts) do
    adapter().create_session_cookie(id_token, opts)
  end

  defp adapter do
    Application.get_env(
      :fireauth,
      :session_cookie_creator_adapter,
      Fireauth.SessionCookie
    )
  end
end
