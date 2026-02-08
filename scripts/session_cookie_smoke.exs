defmodule Fireauth.Scripts.SessionCookieSmoke do
  @moduledoc false

  # Defaults requested by user. Avoid hardcoding passwords in the repo.
  @default_email "test2@test.com"
  @default_project_id "totem-dev-bd538"
  @default_service_account_file "totem-dev-bd538-firebase-adminsdk-fbsvc-492627cd5f.json"

  @firebase_rest_base "https://identitytoolkit.googleapis.com/v1"

  def run do
    # Run via `mix run --no-start scripts/session_cookie_smoke.exs`
    Application.ensure_all_started(:req)
    Application.ensure_all_started(:fireauth)

    api_key = env!("FIREBASE_WEB_API_KEY")
    password = env!("FIREBASE_TEST_PASSWORD")

    email = System.get_env("FIREBASE_TEST_EMAIL") || @default_email
    project_id = System.get_env("FIREBASE_PROJECT_ID") || @default_project_id

    sa_file =
      System.get_env("FIREBASE_ADMIN_SERVICE_ACCOUNT_FILE") ||
        Path.expand(@default_service_account_file)

    valid_duration_s =
      System.get_env("FIREBASE_SESSION_VALID_DURATION_S")
      |> parse_int(60 * 60 * 24 * 5)

    IO.puts("Using email=#{email} project_id=#{project_id}")
    IO.puts("Service account file=#{sa_file}")
    IO.puts("Valid duration=#{valid_duration_s}s")

    sa_json = File.read!(sa_file)

    {:ok, id_token} = sign_in_with_password(api_key, email, password)
    IO.puts("Minted ID token bytes=#{byte_size(id_token)}")
    IO.puts("ID token claims:")
    print_jwt_claims(id_token)

    {:ok, session_cookie} =
      Fireauth.create_session_cookie(id_token,
        project_id: project_id,
        valid_duration_s: valid_duration_s,
        firebase_admin_service_account: sa_json
      )

    IO.puts("Session cookie bytes=#{byte_size(session_cookie)}")
    IO.puts("Session cookie claims:")
    print_jwt_claims(session_cookie)

    :ok
  end

  defp sign_in_with_password(api_key, email, password) do
    url = "#{@firebase_rest_base}/accounts:signInWithPassword?key=#{api_key}"

    body = %{
      "email" => email,
      "password" => password,
      "returnSecureToken" => true
    }

    case Req.post(url, json: body) do
      {:ok, %{status: 200, body: %{"idToken" => token}}} when is_binary(token) and token != "" ->
        {:ok, token}

      {:ok, %{status: status, body: resp_body}} ->
        {:error, {:sign_in_http_error, status, resp_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp print_jwt_claims(jwt) when is_binary(jwt) do
    # Do not print the full JWT; only show a small claim subset.
    jose_jwt = JOSE.JWT.peek_payload(jwt)
    claims = Map.get(jose_jwt, :fields, %{})

    subset =
      Map.take(claims, [
        "iss",
        "aud",
        "sub",
        "user_id",
        "email",
        "auth_time",
        "iat",
        "exp"
      ])

    IO.inspect(subset, label: "claims")
  rescue
    _ -> IO.puts("claims: <failed to decode>")
  end

  defp parse_int(nil, default), do: default

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} when n > 0 -> n
      _ -> default
    end
  end

  defp env!(key) do
    case System.get_env(key) do
      v when is_binary(v) and v != "" -> v
      _ -> raise "Missing required env var #{key}"
    end
  end
end

Fireauth.Scripts.SessionCookieSmoke.run()

