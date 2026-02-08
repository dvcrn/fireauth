# Fireauth

Firebase Auth helpers for Elixir apps:

- Verify Firebase ID tokens (RS256) using Google's SecureToken x509 certs.
- (Optional) Mint Firebase session cookies (server-side, requires admin credentials via a service account).
- Plug helpers for both approaches.

## Install

Add to your mix.exs

```
{:fireauth, "~> 0.1.1"},
```

## Two Ways To Use This Library

### 1) ID Tokens (Bearer Headers, No Admin Credentials)

This is the simplest integration if your client is JavaScript and can send:

`Authorization: Bearer <idToken>`

Fireauth will verify that ID token and attach claims/user info to `conn.assigns`.
This does not require any Firebase Admin service account.

#### Minimal Plug Example

```elixir
defmodule MyApp.Router do
  use Plug.Router
  import Plug.Conn

  plug :match

  # Verifies `Authorization: Bearer <idToken>` and assigns `conn.assigns.fireauth`.
  plug Fireauth.Plug,
    serve_hosted_auth?: false,
    # Optional if you set `config :fireauth, firebase_project_id: "..."` (or `FIREBASE_PROJECT_ID`).
    project_id: "your-project-id",
    on_invalid_token: :unauthorized

  plug :dispatch

  get "/protected" do
    case conn.assigns[:fireauth] do
      %{claims: claims, user_attrs: user} ->
        json(conn, 200, %{
          "uid" => user.firebase_uid,
          "email" => user.email,
          "iss" => claims.iss,
          "aud" => claims.aud
        })

      _ ->
        send_resp(conn, 401, "unauthorized")
    end
  end

  match _ do
    send_resp(conn, 404, "not_found")
  end

  defp json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
```

### 2) Session Cookies (Phoenix/LiveView, Requires Admin Credentials To Mint)

If you want a traditional Phoenix/LiveView setup using an `httpOnly` cookie:

1. Client signs in with Firebase JS SDK and obtains an `idToken`
2. Client POSTs that `idToken` to your backend
3. Backend exchanges it for a Firebase session cookie and sets it as `httpOnly`

That exchange requires admin credentials (typically a Firebase Admin service
account). You do not need the Admin SDK library, but you do need the service
account credentials.

#### Minimal Plug Example

```elixir
defmodule MyApp.Router do
  use Plug.Router
  import Plug.Conn

  plug :match

  # 1) Mount endpoints for:
  #    GET  /auth/csrf
  #    POST /auth/session  (exchange idToken -> httpOnly session cookie)
  #    POST /auth/logout
  forward "/auth",
    to: Fireauth.Plug.SessionRouter,
    init_opts: [
      # Optional if you set `config :fireauth, firebase_project_id: "..."` (or `FIREBASE_PROJECT_ID`).
      project_id: "your-project-id",
      # For local dev only; in prod you want true.
      cookie_secure: false,
      # Optional. Default is 5 days. Must be between 300 and 1_209_600 seconds.
      valid_duration_s: 60 * 60 * 24 * 14
    ]

  # 2) Verify the httpOnly cookie on every request and assign `conn.assigns.fireauth`.
  plug Fireauth.Plug.SessionCookie,
    # Optional if you set `config :fireauth, firebase_project_id: "..."` (or `FIREBASE_PROJECT_ID`).
    project_id: "your-project-id",
    on_invalid_cookie: :unauthorized

  plug :dispatch

  get "/protected" do
    case conn.assigns[:fireauth] do
      %{claims: claims, user_attrs: user} ->
        json(conn, 200, %{
          "uid" => user.firebase_uid,
          "email" => user.email,
          "iss" => claims.iss,
          "aud" => claims.aud
        })

      _ ->
        send_resp(conn, 401, "unauthorized")
    end
  end

  match _ do
    send_resp(conn, 404, "not_found")
  end

  defp json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
```

## Configuration

Set your Firebase project id:

```elixir
config :fireauth, firebase_project_id: "your-project-id"
```

Or via env var: `FIREBASE_PROJECT_ID`.

### Session Cookies (Admin Service Account)

To mint session cookies, configure a Firebase Admin service account (JSON) either in config or via env var.

Config:

```elixir
config :fireauth, firebase_admin_service_account: %{
  "client_email" => "firebase-adminsdk-...@your-project.iam.gserviceaccount.com",
  "private_key" => "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n",
  "project_id" => "your-project-id"
}
```

Env var (JSON or base64-encoded JSON):

- `FIREBASE_ADMIN_SERVICE_ACCOUNT='{"type":"service_account",...}'`
- `FIREBASE_ADMIN_SERVICE_ACCOUNT='<base64-json>'`

## Usage

### Token Verification & Identity Helpers

```elixir
{:ok, claims} = Fireauth.verify_id_token(id_token)
user = Fireauth.User.from_claims(claims)

# Check for specific identities (works with both claims and user structs)
if Fireauth.has_identity?(user, "google.com") do
  google_uid = Fireauth.identity(user, "google.com")
end
```

### Create Session Cookie

```elixir
{:ok, session_cookie} = Fireauth.create_session_cookie(id_token, valid_duration_s: 60 * 60 * 24 * 5)
```

This makes a network call to Google (Identity Toolkit) to exchange the ID token
for a session cookie, and requires service account credentials.

### Hosted Auth Files (Optional)

`Fireauth.Plug` can also proxy or serve Firebase hosted auth helper files at
`/__/auth/*` and `/__/firebase/init.json`. Enable this if you want redirect-mode
auth to work on your own domain in modern browsers.

```elixir
plug Fireauth.Plug,
  # Enable hosted auth file handling.
  serve_hosted_auth?: true,
  # :proxy (default) fetches from firebaseapp.com. :static serves local copies.
  hosted_auth_mode: :proxy,
  # Optional if you set `config :fireauth, firebase_project_id: "..."` (or `FIREBASE_PROJECT_ID`).
  project_id: "your-project-id"
```

### Hosted Auth Modes

To support redirect-mode auth in modern browsers (avoiding third-party cookie issues), you must serve Firebase's helper files from your own domain.

1. **`:proxy` (Default):** Transparently proxies requests to `https://<project>.firebaseapp.com`. This is the most robust method. Responses are cached in-memory.
2. **`:static`:** Serves local copies of the helper files embedded in the `fireauth` library. Use this if your environment cannot make outbound requests to Firebase at runtime.

### Caching

This library caches `/__/auth/*` calls in addition to the Google public keys used
to verify ID tokens and session cookies.

## License

MIT
