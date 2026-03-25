# Fireauth

Firebase Auth helpers for Elixir apps:

- Verify Firebase ID tokens (RS256) and session cookies using Google's public keys.
- Mint Firebase session cookies (server-side, requires admin service account).
- Start and finish server-owned OAuth sign-in flows through Identity Platform.
- Send Firebase email-link sign-in emails from the server.
- Plug middleware for token verification, session cookies, and hosted auth files.

## Install

Add to your `mix.exs`:

```elixir
{:fireauth, "~> 0.7.0"},
```

You can also feed the `LLM_SETUP.md` file into your agent to automate setup.

## Configuration

### Project ID (required)

```elixir
config :fireauth, firebase_project_id: "your-project-id"
```

Or via env var: `FIREBASE_PROJECT_ID`.

### API Key (required for server-owned OAuth and email-link flows)

```elixir
config :fireauth, firebase_web_config: %{"apiKey" => "AIza..."}
```

Or via env var: `FIREBASE_API_KEY`.

### Admin Service Account (required for session cookies)

```elixir
config :fireauth, firebase_admin_service_account: %{
  "client_email" => "firebase-adminsdk-...@your-project.iam.gserviceaccount.com",
  "private_key" => "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n",
  "project_id" => "your-project-id"
}
```

Or via env var (JSON or base64-encoded JSON): `FIREBASE_ADMIN_SERVICE_ACCOUNT`.

## Auth Flows

### 1) Popup Flow

The simplest integration. The client signs in with the Firebase JS SDK popup,
obtains an ID token, and sends it to your backend. No hosted auth files needed.

**Option A: Bearer header** — client sends `Authorization: Bearer <idToken>` on
each request. Stateless, no admin credentials required.

```elixir
defmodule MyApp.Router do
  use Plug.Router

  plug :match
  plug Fireauth.Plug, on_invalid_token: :unauthorized
  plug :dispatch

  get "/protected" do
    case conn.assigns[:fireauth] do
      %{user: user} -> send_resp(conn, 200, "Hello #{user.email}")
      _ -> send_resp(conn, 401, "unauthorized")
    end
  end
end
```

**Option B: Session cookie** — client POSTs the ID token once, backend mints an
`httpOnly` cookie. Better for Phoenix/LiveView. Requires admin credentials.

```elixir
# Mount session endpoints (outside your :browser pipeline to avoid Phoenix CSRF conflicts)
forward "/auth/firebase",
  to: Fireauth.Plug.SessionRouter,
  init_opts: [cookie_secure: false]  # true in production

# Verify session cookie on every request
plug Fireauth.Plug.SessionCookie, on_invalid_cookie: :unauthorized
```

The client exchanges its ID token for a session cookie:

```javascript
// After signInWithPopup succeeds:
const idToken = await user.getIdToken();
const csrf = await fetch("/auth/firebase/csrf").then(r => r.json());
await fetch("/auth/firebase/session", {
  method: "POST",
  headers: { "content-type": "application/json", "x-csrf-token": csrf.csrfToken },
  body: JSON.stringify({ idToken, csrfToken: csrf.csrfToken })
});
```

### 2) Redirect Flow

Uses Firebase's `signInWithRedirect`. Requires serving Firebase's hosted auth
files from your domain (modern browsers block third-party cookies). Fireauth
provides `Fireauth.Snippets.client/1` to wire the client-side start/verify flow
without a bundler.

**Endpoint setup** — serve hosted auth files before your router:

- `HostedController` means we're serving static html from Fireauth itself
- `ProxyController` means we're proxying the requests to upstream Google

```elixir
# In your Endpoint (before the router)
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

**Session endpoints + cookie verification** (same as popup Option B):

```elixir
forward "/auth/firebase",
  to: Fireauth.Plug.SessionRouter,
  init_opts: [cookie_secure: false]

plug Fireauth.Plug.SessionCookie
```

**Start page** — embed the snippet and trigger redirect:

```elixir
# In your template (HEEx)
{Fireauth.Snippets.client(return_to: @return_to, session_base: "/auth/firebase", debug: true)}

<script>
  fireauth.start(
    { provider: "google.com", ready: () => !!window.myFirebaseAuth },
    function (providerId) {
      const auth = firebase.auth.getAuth();
      return firebase.auth.signInWithRedirect(auth, new firebase.auth.GoogleAuthProvider());
    }
  )
  .error(s => console.warn("start error", s.code, s.message))
  .onStateChange(s => console.debug("state", s.stage));
</script>
```

**Verify page** — resolves the returning user and exchanges the token:

```elixir
{Fireauth.Snippets.client(return_to: @return_to, session_base: "/auth/firebase")}

<script>
  fireauth.verify(
    { requireVerified: true, getAuth: () => firebase.auth.getAuth() },
    function (s) {
      if (s.type === "error") showError(s.message);
      if (s.loading) showLoading(s.message);
    }
  )
  .success(() => showLoading("Login successful. Redirecting..."))
  .error(s => showError(s.message));
</script>
```

### 3) Server-Owned OAuth Flow

The server drives the OAuth redirect directly via Identity Platform APIs. No
Firebase JS SDK is needed for the auth flow itself — useful when you want full
control over the login UX without Firebase's redirect/popup screens.

```elixir
# 1. Start: build provider redirect URL
{:ok, start_result} =
  Fireauth.start_oauth_sign_in("google.com", "https://example.com/auth/callback/google",
    otp_app: :my_app
  )

# Redirect browser to the provider
redirect(conn, external: start_result.auth_uri)
# Save start_result.session_id (e.g. in the session) for the callback
```

```elixir
# 2. Callback: exchange the provider response for a Firebase ID token
{:ok, sign_in_result} =
  Fireauth.finish_oauth_sign_in(
    # The full callback URL including query params
    "https://example.com/auth/callback/google?code=abc",
    session_id,  # from step 1
    nil,
    otp_app: :my_app
  )

# 3. Optionally mint a session cookie
{:ok, session_cookie} =
  Fireauth.create_session_cookie(sign_in_result.firebase_id_token,
    otp_app: :my_app,
    valid_duration_s: 60 * 60 * 24 * 14
  )
```

`finish_oauth_sign_in/4` returns a `%Fireauth.ServerAuth.SignInResult{}` with
`firebase_id_token`, `email`, `display_name`, `is_new_user`, and more.

## Helpers

### Token & Session

```elixir
# Verify a Firebase ID token (RS256)
{:ok, claims} = Fireauth.verify_id_token(id_token)

# Verify a Firebase session cookie
{:ok, claims} = Fireauth.verify_session_cookie(cookie)

# Exchange an ID token for a session cookie (requires admin service account)
{:ok, cookie} = Fireauth.create_session_cookie(id_token,
  valid_duration_s: 60 * 60 * 24 * 14  # max 14 days, default 5 days
)
```

### User & Identity

```elixir
# Convert claims to a user struct
user = Fireauth.claims_to_user_attrs(claims)
# => %Fireauth.User{firebase_uid: "...", email: "...", name: "...", ...}

# Check provider identities (works with claims, user, or %Fireauth{} struct)
Fireauth.has_identity?(user, "google.com")  # => true/false
Fireauth.identity(user, "google.com")       # => "google-uid" or nil
Fireauth.identities(user)                   # => %{"google.com" => ["..."], ...}
```

### Server-Owned Auth

```elixir
# Start a server-owned OAuth sign-in
{:ok, %Fireauth.ServerAuth.StartResult{auth_uri: url, session_id: sid}} =
  Fireauth.start_oauth_sign_in("google.com", callback_url, otp_app: :my_app)

# Finish the OAuth callback
{:ok, %Fireauth.ServerAuth.SignInResult{firebase_id_token: token}} =
  Fireauth.finish_oauth_sign_in(request_uri, session_id, post_body, otp_app: :my_app)

# Send an email-link sign-in email
{:ok, %Fireauth.EmailLinkSender.Result{email: email}} =
  Fireauth.send_email_sign_in_link("user@example.com", continue_url, otp_app: :my_app)
```

`send_email_sign_in_link/3` sends the Firebase email-link sign-in email via
Identity Toolkit (`accounts:sendOobCode`). Completing the sign-in still uses the
Firebase Web SDK on your verify page via `signInWithEmailLink(...)`.

### Custom Tokens & Account Management

```elixir
# Mint a custom token for server-side auth flows (e.g. signInWithCustomToken)
{:ok, custom_token} = Fireauth.create_custom_token("user-123", claims: %{"role" => "admin"})

# Exchange a custom token for a Firebase ID token (server-side)
{:ok, id_token} = Fireauth.exchange_custom_token(custom_token, otp_app: :my_app)

# Unlink a provider from a user
{:ok, _response} = Fireauth.unlink_provider(id_token, "google.com", otp_app: :my_app)
```

### Plugs

| Plug | Purpose |
|------|---------|
| `Fireauth.Plug` | Verifies `Authorization: Bearer <idToken>` and serves hosted auth files via `callback_overrides` |
| `Fireauth.Plug.SessionRouter` | Mounts `GET /csrf`, `POST /session`, `POST /logout` endpoints for session cookie flow |
| `Fireauth.Plug.SessionCookie` | Verifies the `httpOnly` session cookie and attaches `conn.assigns.fireauth` |
| `Fireauth.Plug.FirebaseAuthProxy` | Transparent reverse proxy for Firebase hosted auth files |

**`Fireauth.Plug` options:**

- `:on_invalid_token` — `:ignore` (default), `:unauthorized`, or `{:assign_error, key}`
- `:callback_overrides` — map of path to controller for hosted auth routing
- `:default_controller` — fallback for unmatched hosted paths (default: `Fireauth.HostedController`, set `nil` to disable)

**`Fireauth.Plug.SessionRouter` options:**

- `:valid_duration_s` — cookie lifetime in seconds (300–1,209,600, default: 432,000 = 5 days)
- `:cookie_secure` — `true` in production, `false` for local dev
- `:cookie_same_site` — default `"Lax"`
- `:session_cookie_name` — default `"session"`
- `:csrf_cookie_name` — default `"fireauth_csrf"`

**`Fireauth.Plug.SessionCookie` options:**

- `:on_invalid_cookie` — `:ignore` (default), `:unauthorized`, or `{:assign_error, key}`
- `:cookie_name` — default `"session"`

### Snippets

`Fireauth.Snippets` provides HEEx-embeddable helpers (depends on `phoenix_html`, not `phoenix`):

| Function | Purpose |
|----------|---------|
| `client(opts)` | Embeds the `window.fireauth` client API (`start` + `verify`) |
| `hosted_auth_handler_bootstrap/0` | Firebase bootstrap `<script>` tags for `/__/auth/handler` |
| `hosted_auth_handler_document/0` | Full HTML document for `/__/auth/handler` |
| `hosted_auth_iframe_bootstrap/0` | Firebase bootstrap `<script>` tags for `/__/auth/iframe` |
| `hosted_auth_iframe_document/0` | Full HTML document for `/__/auth/iframe` |

**`client/1` options:**

- `:return_to` — where to redirect after session is established (default: `"/"`)
- `:session_base` — mount path for `SessionRouter` (default: `"/auth/firebase"`)
- `:require_verified` — require verified email (default: `true`)
- `:debug` — enable `[fireauth]` console logging (default: `false`)

**`window.fireauth` API:**

- `start(opts, callback)` — call your callback to trigger Firebase redirect. Supports `opts.ready` (polled until truthy) and `opts.readyTimeout` (default 5000ms).
- `verify(opts, callback)` — resolve current user via `opts.getAuth()`, exchange ID token for session cookie, redirect to `return_to`. Returns chainable `.success(cb).error(cb).onStateChange(cb)`.
- `onStateChange(cb)` / `onError(cb)` / `onSuccess(cb)` — global listeners.

### Hosted Auth Routing

To support redirect-mode auth, serve Firebase's helper files from your domain
using `callback_overrides`. Two controller options:

- **`Fireauth.HostedController`** — serves local snippet-based HTML for `handler` and `iframe`, proxies `action` and `action.js` to Firebase upstream.
- **`Fireauth.ProxyController`** — transparently proxies everything to `https://<project>.firebaseapp.com` with in-memory caching.

## License

MIT

---

## Appendix: Custom Auth Handler

Firebase's default `/__/auth/handler` page shows its own loading indicators and
UI during the redirect flow. If you want to replace that with your own branded
page, override the path with a `{Module, :action}` tuple in `callback_overrides`:

```elixir
plug Fireauth.Plug,
  callback_overrides: %{
    "/__/auth/handler" => {MyAppWeb.FirebaseHostedAuthController, :handler},
    "/__/auth/handler.js" => Fireauth.ProxyController,
    "/__/firebase/init.json" => Fireauth.HostedController
  }
```

Your controller must include `Fireauth.Snippets.hosted_auth_handler_bootstrap/0`
to preserve Firebase's auth relay behavior. You can then hide Firebase's injected
containers with CSS and render your own UI:

```elixir
defmodule MyAppWeb.FirebaseHostedAuthController do
  use MyAppWeb, :controller

  def handler(conn, _params) do
    body = """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      #{Fireauth.Snippets.hosted_auth_handler_bootstrap()}
      <style>
        /* Hide Firebase's injected UI */
        #pending-screen, #continue-screen, #error-screen,
        .firebase-container { display: none !important; }
      </style>
    </head>
    <body>
      <main>Completing authentication...</main>
    </body>
    </html>
    """

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, body)
    |> halt()
  end
end
```

If you just want the default Firebase handler served from your own controller
without customization:

```elixir
def handler(conn, _params) do
  conn
  |> put_resp_content_type("text/html")
  |> send_resp(200, Fireauth.Snippets.hosted_auth_handler_document())
  |> halt()
end
```
