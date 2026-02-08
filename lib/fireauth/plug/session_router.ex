defmodule Fireauth.Plug.SessionRouter do
  @moduledoc """
  Plug that provides endpoints for session-cookie login/logout.

  Mount it under your app, for example:

      forward "/auth", Fireauth.Plug.SessionRouter, []

  Endpoints (relative to the mount path):

  - `GET /csrf` - sets a non-httpOnly CSRF cookie and returns the token as JSON
  - `POST /session` - exchanges `idToken` for a session cookie and sets it as httpOnly
  - `POST /logout` - clears the session cookie

  CSRF protection uses the "double submit cookie" pattern: the client must send
  the CSRF token both as a cookie (set by `GET /csrf`) and as either a request
  header (`x-csrf-token`) or JSON param (`csrfToken`).
  """

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts) when is_list(opts) do
    opts
    |> Keyword.put_new(:csrf_cookie_name, "fireauth_csrf")
    |> Keyword.put_new(:session_cookie_name, "session")
    |> Keyword.put_new(:valid_duration_s, 60 * 60 * 24 * 5)
    |> Keyword.put_new(:cookie_secure, true)
    |> Keyword.put_new(:cookie_same_site, "Lax")
    |> Keyword.put_new(:cookie_path, "/")
    |> Keyword.put_new(:create_session_cookie_fun, &Fireauth.create_session_cookie/2)
  end

  @impl true
  def call(conn, opts) do
    conn
    |> put_private(:fireauth_opts, opts)
    |> __MODULE__.Router.call([])
  end

  defmodule Router do
    @moduledoc false

    use Plug.Router

    import Plug.Conn

    @csrf_header "x-csrf-token"

    plug(:match)

    plug(Plug.Parsers,
      parsers: [:json],
      pass: ["application/json"],
      json_decoder: Jason
    )

    plug(:dispatch)

    get "/csrf" do
      opts = conn.private[:fireauth_opts] || []
      conn = fetch_cookies(conn)

      token = random_token()

      conn =
        put_resp_cookie(conn, Keyword.fetch!(opts, :csrf_cookie_name), token,
          http_only: false,
          secure: Keyword.fetch!(opts, :cookie_secure),
          same_site: Keyword.fetch!(opts, :cookie_same_site),
          path: Keyword.fetch!(opts, :cookie_path)
        )

      json(conn, 200, %{"csrfToken" => token})
    end

    post "/session" do
      opts = conn.private[:fireauth_opts] || []
      conn = fetch_cookies(conn)

      with :ok <- verify_csrf(conn, opts),
           {:ok, id_token} <- fetch_param(conn, "idToken"),
           :ok <- validate_duration(opts),
           {:ok, cookie} <- mint_cookie(id_token, opts) do
        max_age = Keyword.fetch!(opts, :valid_duration_s)

        conn =
          put_resp_cookie(conn, Keyword.fetch!(opts, :session_cookie_name), cookie,
            http_only: true,
            secure: Keyword.fetch!(opts, :cookie_secure),
            same_site: Keyword.fetch!(opts, :cookie_same_site),
            path: Keyword.fetch!(opts, :cookie_path),
            max_age: max_age
          )

        json(conn, 200, %{"status" => "ok"})
      else
        {:error, :csrf_invalid} ->
          json(conn, 403, %{"error" => "csrf_invalid"})

        {:error, :missing_param} ->
          json(conn, 400, %{"error" => "missing_param"})

        {:error, :invalid_valid_duration} ->
          json(conn, 400, %{"error" => "invalid_valid_duration"})

        {:error, reason} ->
          json(conn, 401, %{"error" => "unauthorized", "reason" => inspect(reason)})
      end
    end

    post "/logout" do
      opts = conn.private[:fireauth_opts] || []

      conn =
        delete_resp_cookie(conn, Keyword.fetch!(opts, :session_cookie_name),
          path: Keyword.fetch!(opts, :cookie_path)
        )

      json(conn, 200, %{"status" => "ok"})
    end

    match _ do
      send_resp(conn, 404, "not found")
    end

    defp mint_cookie(id_token, opts) do
      create_fun = Keyword.fetch!(opts, :create_session_cookie_fun)

      fireauth_opts =
        opts
        |> Keyword.drop([
          :csrf_cookie_name,
          :session_cookie_name,
          :cookie_secure,
          :cookie_same_site,
          :cookie_path,
          :create_session_cookie_fun
        ])

      create_fun.(id_token, fireauth_opts)
    end

    defp validate_duration(opts) do
      seconds = Keyword.fetch!(opts, :valid_duration_s)

      cond do
        not is_integer(seconds) -> {:error, :invalid_valid_duration}
        seconds < 300 -> {:error, :invalid_valid_duration}
        seconds > 1_209_600 -> {:error, :invalid_valid_duration}
        true -> :ok
      end
    end

    defp verify_csrf(conn, opts) do
      cookie_name = Keyword.fetch!(opts, :csrf_cookie_name)
      cookie_token = Map.get(conn.req_cookies, cookie_name)

      req_token =
        case get_req_header(conn, @csrf_header) do
          [v | _] when is_binary(v) and v != "" -> v
          _ -> nil
        end || Map.get(conn.params, "csrfToken")

      if is_binary(cookie_token) and cookie_token != "" and cookie_token == req_token do
        :ok
      else
        {:error, :csrf_invalid}
      end
    end

    defp fetch_param(conn, key) when is_binary(key) do
      case Map.get(conn.params, key) do
        v when is_binary(v) and v != "" -> {:ok, v}
        _ -> {:error, :missing_param}
      end
    end

    defp random_token do
      32
      |> :crypto.strong_rand_bytes()
      |> Base.url_encode64(padding: false)
    end

    defp json(conn, status, %{} = body) do
      payload = Jason.encode!(body)

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(status, payload)
      |> halt()
    end
  end
end
