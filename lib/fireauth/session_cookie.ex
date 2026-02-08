defmodule Fireauth.SessionCookie do
  @moduledoc """
  Mint Firebase Auth session cookies using a Firebase Admin service account.

  This performs a network call to Google's Identity Toolkit API
  (`projects.createSessionCookie`), which requires OAuth (service account
  credentials).
  """

  alias Fireauth.Admin.OAuth
  alias Fireauth.Admin.ServiceAccount
  alias Fireauth.Config

  @identitytoolkit_base "https://identitytoolkit.googleapis.com/v1"

  @type id_token :: String.t()
  @type session_cookie :: String.t()

  @doc """
  Exchange a Firebase ID token for a Firebase session cookie.

  This makes a network call to Google to exchange the given ID token for a
  session cookie.

  Options:

  - `:project_id` - Firebase project id (falls back to config/env/service account project_id)
  - `:valid_duration_s` - cookie lifetime in seconds (300..1_209_600). Default: 432_000 (5 days).
  - `:firebase_admin_service_account` - map or JSON string (or base64 JSON). Falls back to config/env.
  """
  @spec exchange_id_token(id_token(), keyword()) :: {:ok, session_cookie()} | {:error, term()}
  def exchange_id_token(id_token, opts \\ []) when is_binary(id_token) and is_list(opts) do
    valid_duration_s = Keyword.get(opts, :valid_duration_s, 60 * 60 * 24 * 5)

    with :ok <- validate_duration(valid_duration_s),
         {:ok, sa} <- load_service_account(opts),
         {:ok, project_id} <- resolve_project_id(opts, sa),
         {:ok, access_token} <- OAuth.fetch_access_token(sa, opts) do
      create_session_cookie(project_id, id_token, valid_duration_s, access_token)
    end
  end

  defp load_service_account(opts) do
    value =
      Keyword.get(opts, :firebase_admin_service_account) ||
        Config.firebase_admin_service_account(opts)

    ServiceAccount.decode(value)
  end

  defp resolve_project_id(opts, sa) do
    case Config.firebase_project_id(opts) || Map.get(sa, "project_id") do
      pid when is_binary(pid) and pid != "" -> {:ok, pid}
      _ -> {:error, :missing_project_id}
    end
  end

  defp validate_duration(seconds) when is_integer(seconds) do
    cond do
      seconds < 300 -> {:error, :invalid_valid_duration}
      seconds > 1_209_600 -> {:error, :invalid_valid_duration}
      true -> :ok
    end
  end

  defp validate_duration(_), do: {:error, :invalid_valid_duration}

  defp create_session_cookie(project_id, id_token, valid_duration_s, access_token)
       when is_binary(project_id) and is_binary(id_token) and is_integer(valid_duration_s) and
              is_binary(access_token) do
    url = "#{@identitytoolkit_base}/projects/#{project_id}:createSessionCookie"

    body = %{
      "idToken" => id_token,
      # API expects seconds as a string.
      "validDuration" => Integer.to_string(valid_duration_s)
    }

    headers = [
      {"authorization", "Bearer #{access_token}"}
    ]

    case Req.post(url, json: body, headers: headers) do
      {:ok, %{status: 200, body: %{"sessionCookie" => cookie}}}
      when is_binary(cookie) and cookie != "" ->
        {:ok, cookie}

      {:ok, %{status: status, body: body}} ->
        {:error, {:create_session_cookie_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
