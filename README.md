# Fireauth

Firebase Auth helpers for Elixir apps:

- Verify Firebase ID tokens (RS256) using Google's SecureToken x509 certs.
- (Optional) Mint Firebase session cookies (server-side, requires admin credentials via a service account).
- Plug helpers for both approaches.

## Install

Add to your mix.exs

```
{:fireauth, "~> 0.4.0"},
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
    # Optional: disable hosted callback handling in this plug instance.
    default_controller: nil,
    # Optional if you set `config :fireauth, firebase_project_id: "..."` (or `FIREBASE_PROJECT_ID`).
    project_id: "your-project-id",
    on_invalid_token: :unauthorized

  plug :dispatch

  get "/protected" do
    case conn.assigns[:fireauth] do
      %{claims: claims, user: user} ->
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
      %{claims: claims, user: user} ->
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

`Fireauth.Plug` can route Firebase hosted auth helper paths at `/__/auth/*` and
`/__/firebase/init.json` via `callback_overrides`. Enable this if you want
redirect-mode auth to work on your own domain in modern browsers.

```elixir
plug Fireauth.Plug,
  # Exact path overrides (overrides-only mode).
  callback_overrides: %{
    "/__/auth/handler" => {MyAppWeb.FirebaseHostedAuthController, :handler},
    "/__/firebase/init.json" => Fireauth.ProxyController,
    "/__/auth/handler.js" => Fireauth.HostedController
  },
  # Optional if you set `config :fireauth, firebase_project_id: "..."` (or `FIREBASE_PROJECT_ID`).
  project_id: "your-project-id"
```

When `callback_overrides` is present, only paths in that map are handled.
Unlisted managed callback paths fall back to `default_controller` (defaults to
`Fireauth.HostedController`). Set `default_controller: nil` to disable fallback.

### Redirect-Mode Client Helper (Optional)

Fireauth ships a JavaScript helper via `Fireauth.Snippets.client/1` to make this flow easier:

1. Redirect the user to a `/start/` page with POST: Starts firebase auth flow, redirects to oauth screen, etc
2. Firebase redirects back to the `/start/` with GET: Show loading indicator, exchange idToken for session cookie, redirect to main page

It exposes:

- `window.fireauth.start(opts, callback)`:
  - executes your callback to start Firebase redirect
  - supports `opts.ready` — a function polled until truthy before invoking the callback (useful when the Firebase SDK loads asynchronously via a deferred script)
  - supports `opts.readyTimeout` — max ms to wait (default 5000)
- `window.fireauth.verify(opts, callback)`:
  - resolves current user from `opts.getAuth()`
  - calls `currentUser.getIdToken()`
  - exchanges `idToken` for session cookie
  - redirects to `return_to`
  - supports chaining: `.success(...).error(...).onStateChange(...)`

Optional UI integration:

- `window.fireauth.onStateChange/1`, `window.fireauth.onError/1`, `window.fireauth.onSuccess/1`

#### Server Setup

1. Ensure hosted auth files are served at the endpoint level (so `/__/auth/handler` is not a 404):

```elixir
# In your Endpoint (Phoenix) or top-level Plug stack (Plug.Router),
# before your router.
plug Fireauth.Plug,
  callback_overrides: %{
    "/__/auth/handler" => Fireauth.HostedController,
    "/__/auth/iframe" => Fireauth.HostedController,
    "/__/auth/handler.js" => Fireauth.HostedController,
    "/__/auth/iframe.js" => Fireauth.HostedController,
    "/__/auth/experiments.js" => Fireauth.HostedController,
    "/__/firebase/init.json" => Fireauth.ProxyController
  }
```

2. Mount the session endpoints (cookie minting) and verify cookies on requests:

```elixir
forward "/auth/firebase",
  to: Fireauth.Plug.SessionRouter,
  init_opts: [cookie_secure: false]

plug Fireauth.Plug.SessionCookie
```

#### Snippet Setup

In any HEEx template (requires `phoenix_html`), embed the snippet:

```elixir
{Fireauth.Snippets.client(
  return_to: @return_to,
  session_base: "/auth/firebase",
  debug: true
)}
```

#### Start Flow

```html
<script>
  function buildProvider(providerId) {
    const authNs = window.firebase.auth;

    if (
      providerId.indexOf("github") !== -1 &&
      typeof authNs.GithubAuthProvider === "function"
    ) {
      return new authNs.GithubAuthProvider();
    }

    if (
      providerId.indexOf("google") !== -1 &&
      typeof authNs.GoogleAuthProvider === "function"
    ) {
      return new authNs.GoogleAuthProvider();
    }

    return null;
  }

  fireauth
    .start(
      {
        provider: "github.com",
        // Wait for the Firebase SDK to be available before starting.
        // Useful when the app bundle is loaded with <script defer>.
        ready: function () {
          return !!window.myFirebaseAuth;
        },
        // Optional: max ms to wait (default 5000)
        // readyTimeout: 3000,
      },
      function (providerId, ctx) {
        const auth = window.firebase.auth.getAuth();
        const authNs = window.firebase.auth;
        const signInWithRedirect = authNs.signInWithRedirect;

        const provider = buildProvider(providerId);
        if (!provider) {
          throw new Error("Unsupported provider: " + String(providerId || ""));
        }

        return signInWithRedirect(auth, provider);
      },
    )
    .error(function (s) {
      console.warn("start error", s.code, s.message);
    })
    .onStateChange(function (s) {
      console.debug("start state", s.stage);
    });
</script>
```

#### Verify Flow

```html
<script>
  fireauth
    .verify(
      { requireVerified: true, getAuth: window.firebase.auth.getAuth },
      function (s) {
        if (!s) return;
        if (s.type === "error")
          return showError(s.message || statusEl.textContent);
        if (s.loading) return showLoading(s.message || statusEl.textContent);
      },
    )
    .success(function () {
      showLoading("Login successful. Redirecting...");
    })
    .error(function (s) {
      showError((s && s.message) || statusEl.textContent);
    });
</script>
```

### Hosted Auth Routing

To support redirect-mode auth in modern browsers (avoiding third-party cookie issues), you must serve Firebase's helper files from your own domain.

1. **`callback_overrides`:** exact-path overrides for specific hosted callback paths.
2. **`Fireauth.ProxyController`:** proxies requests to `https://<project>.firebaseapp.com` with in-memory caching.
3. **`default_controller` (default: `Fireauth.HostedController`):** fallback controller for managed hosted callback paths not listed in `callback_overrides`.
4. **`Fireauth.HostedController`:** serves local hosted files, and renders snippet-based HTML for `"/__/auth/handler"` and `"/__/auth/iframe"`.

### Hosted Handler Snippets

If you override `"/__/auth/handler"` with your own controller, use these helpers
to keep Firebase bootstrap behavior consistent:

- `Fireauth.Snippets.hosted_auth_handler_bootstrap/0`
- `Fireauth.Snippets.hosted_auth_handler_document/0`

Example controller for `callback_overrides`:

```elixir
defmodule MyAppWeb.FirebaseHostedAuthController do
  use MyAppWeb, :controller

  # Used by:
  # "/__/auth/handler" => {MyAppWeb.FirebaseHostedAuthController, :handler}
  def handler(conn, _params) do
    conn
    |> Plug.Conn.put_resp_content_type("text/html")
    |> Plug.Conn.send_resp(200, Fireauth.Snippets.hosted_auth_handler_document())
    |> Plug.Conn.halt()
  end
end
```

If you need custom HTML, keep Firebase bootstrap by including
`Fireauth.Snippets.hosted_auth_handler_bootstrap/0`:

```elixir
def handler(conn, _params) do
  body = """
  <!DOCTYPE html>
  <html>
  <head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
    #{Fireauth.Snippets.hosted_auth_handler_bootstrap()}
  </head>
  <body></body>
  </html>
  """

  conn
  |> Plug.Conn.put_resp_content_type("text/html")
  |> Plug.Conn.send_resp(200, body)
  |> Plug.Conn.halt()
end
```

### Caching

This library caches `/__/auth/*` calls in addition to the Google public keys used
to verify ID tokens and session cookies.

## License

MIT
