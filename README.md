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
{:fireauth, "~> 0.8.0"},
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
obtains an ID token, and sends it to your backend. No hosted auth files or
special routing required — just the Firebase JS SDK on the client.

There are two ways to pass the authenticated identity to your server:

**Option A: Bearer token** — the client stores the ID token (e.g. in a cookie
or `localStorage`) and sends it as `Authorization: Bearer <idToken>` on every
request. The server verifies the token on each request. This is fully stateless
on the server and does not require admin credentials, but the client is
responsible for token storage and refresh.

```elixir
# In your router or endpoint
plug Fireauth.Plug, on_invalid_token: :unauthorized
```

```elixir
# In a route or controller
case conn.assigns[:fireauth] do
  %{user: user} -> send_resp(conn, 200, "Hello #{user.email}")
  _ -> send_resp(conn, 401, "unauthorized")
end
```

On the client side:

```javascript
// After signInWithPopup succeeds:
const idToken = await user.getIdToken();

// Store and send on every request
fetch("/api/data", {
  headers: { "Authorization": `Bearer ${idToken}` }
});
```

**Option B: Session cookie** — the client sends the ID token once, and the
server mints a long-lived `httpOnly` session cookie. After that, the browser
sends the cookie automatically — no need to manage tokens on the client. This
is the better choice for Phoenix/LiveView apps where you need the session
available on WebSocket connect, and for any app that wants automatic cookie
handling instead of manual `Authorization` headers.

Requires an admin service account (see Configuration above).

```elixir
# Mount session endpoints (outside your :browser pipeline to avoid Phoenix CSRF conflicts)
forward "/auth/firebase",
  to: Fireauth.Plug.SessionRouter,
  init_opts: [cookie_secure: false]  # true in production

# Verify session cookie on every request
plug Fireauth.Plug.SessionCookie, on_invalid_cookie: :unauthorized
```

On the client side, exchange the ID token for a session cookie once after login:

```javascript
// After signInWithPopup succeeds:
const idToken = await user.getIdToken();

// 1. Get a CSRF token
const csrf = await fetch("/auth/firebase/csrf").then(r => r.json());

// 2. Exchange idToken for a session cookie (set automatically as httpOnly)
await fetch("/auth/firebase/session", {
  method: "POST",
  headers: { "content-type": "application/json", "x-csrf-token": csrf.csrfToken },
  body: JSON.stringify({ idToken, csrfToken: csrf.csrfToken })
});

// From here on, the browser sends the session cookie automatically.
// No need to pass the idToken again.
```

### 2) Redirect Flow

Uses Firebase's `signInWithRedirect` instead of a popup. This is needed when
popups are blocked (mobile browsers, embedded webviews) or when you want a
full-page login experience.

**Why two pages?** Firebase's redirect flow works like this:

1. **Start page** — your login page calls `signInWithRedirect(...)`, which
   navigates the browser away to the provider (e.g. Google). Before leaving,
   Firebase stores pending state in the browser.
2. The provider authenticates the user and redirects back to Firebase's
   `/__/auth/handler` page on your domain.
3. **Verify page** — after Firebase's handler resolves the auth result, the
   browser lands back on your app. This page calls `getRedirectResult()` to
   pick up the authenticated user, exchanges the ID token for a session cookie,
   and redirects to the final destination.

A convenient pattern is to use one route path with GET and POST — the GET
renders the login form (start), and the POST handles the return from the
provider redirect (verify). Since the redirect back from the provider arrives
as a POST, the router naturally separates the two phases:

```elixir
# In your router
get "/auth/firebase/start", FirebaseAuthController, :start
post "/auth/firebase/start", FirebaseAuthController, :create
```

```elixir
defmodule MyAppWeb.FirebaseAuthController do
  use MyAppWeb, :controller

  def start(conn, _params) do
    # Render login page with fireauth.start(...)
    render(conn, :start, return_to: get_session(conn, :return_to) || "/")
  end

  def create(conn, _params) do
    # Render verify page with fireauth.verify(...)
    render(conn, :create, return_to: get_session(conn, :return_to) || "/")
  end
end
```

You can also use the same page for both if you prefer — but splitting by HTTP
method keeps each template focused.

**Requirement: hosted auth files.** Modern browsers block third-party cookies,
so Firebase's `/__/auth/handler` and `/__/auth/iframe` pages must be served
from your own domain. Fireauth provides two controllers for this:

- `Fireauth.HostedController` — serves locally-rendered HTML from Fireauth
- `Fireauth.ProxyController` — proxies requests to upstream Firebase

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

**Start template** (`start.html.heex`) — your login page. Embed the snippet
and trigger the redirect:

```elixir
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

**Verify template** (`create.html.heex`) — the page rendered on POST when the
provider redirect returns. It resolves the authenticated user, exchanges the ID
token for a session cookie, and redirects to `return_to`:

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

The server drives the entire OAuth redirect through Identity Platform APIs.
No Firebase JS SDK is needed for the auth flow — your server builds the
redirect URL, sends the user to the provider, and handles the callback itself.
This gives you full control over the login UX and is the right choice when you
don't want to load the Firebase JS SDK at all, or when you need server-side
logic (e.g. account linking, custom claims) before the session is established.

**Requirements:**
- Firebase API key (configured via `firebase_web_config` or `FIREBASE_API_KEY`)
- Admin service account (if you want to mint session cookies after sign-in)
- A controller with start and callback actions
- Routes for both GET and POST callbacks (some providers like Apple POST the
  callback cross-site)

**How it works:**

1. User clicks "Sign in with Google" on your page
2. Your server calls `Fireauth.start_oauth_sign_in/3` to get a redirect URL
   from Identity Platform, stores the `session_id` in the Plug session
3. You redirect the browser to the provider (Google, Apple, etc.)
4. The provider redirects back to your callback URL with an authorization code
5. Your server calls `Fireauth.finish_oauth_sign_in/4` to exchange the code
   for a Firebase ID token
6. Mint a session cookie with `Fireauth.create_session_cookie/2` and set it

**Router setup:**

```elixir
scope "/", MyAppWeb do
  pipe_through :browser

  get "/auth/firebase/start", AuthController, :start
  post "/auth/firebase/start", AuthController, :create
  get "/auth/callback/:provider", AuthController, :callback
end

# Some providers (e.g. Apple) POST the callback cross-site. The POST needs
# its own pipeline without CSRF protection since it comes from the provider.
scope "/", MyAppWeb do
  pipe_through :oauth_callback

  post "/auth/callback/:provider", AuthController, :callback
end
```

**Controller:**

```elixir
defmodule MyAppWeb.AuthController do
  use MyAppWeb, :controller

  @oauth_flow_session_key :firebase_oauth_flow

  # GET /auth/firebase/start?provider=google — render login page
  def start(conn, %{"provider" => provider}) do
    create(conn, %{"provider" => provider})
  end

  def start(conn, _params) do
    render(conn, :start)
  end

  # POST /auth/firebase/start — start the server-side OAuth flow
  def create(conn, %{"provider" => provider}) do
    callback_uri = url(conn, ~p"/auth/callback/#{provider}")

    {:ok, start_result} =
      Fireauth.start_oauth_sign_in("#{provider}.com", callback_uri, otp_app: :my_app)

    conn
    |> put_session(@oauth_flow_session_key, %{
      session_id: start_result.session_id,
      started_at: System.system_time(:second)
    })
    |> redirect(external: start_result.auth_uri)
  end

  # POST /auth/callback/:provider — some providers (Apple) POST cross-site.
  # The SameSite=Lax session cookie won't be sent on cross-site POSTs, so
  # redirect to GET on our own domain to recover the session cookie.
  def callback(%{method: "POST"} = conn, %{"provider" => provider} = params) do
    query =
      params
      |> Map.take(["code", "state", "id_token", "user"])
      |> URI.encode_query()

    redirect(conn, to: "/auth/callback/#{provider}?#{query}")
  end

  # GET /auth/callback/:provider — complete the OAuth flow
  def callback(conn, _params) do
    oauth_flow = get_session(conn, @oauth_flow_session_key)

    {:ok, sign_in_result} =
      Fireauth.finish_oauth_sign_in(
        Plug.Conn.request_url(conn),
        oauth_flow.session_id,
        nil,
        otp_app: :my_app
      )

    # sign_in_result has: firebase_id_token, email, display_name, is_new_user, etc.

    {:ok, session_cookie} =
      Fireauth.create_session_cookie(sign_in_result.firebase_id_token,
        otp_app: :my_app,
        valid_duration_s: 60 * 60 * 24 * 14
      )

    conn
    |> delete_session(@oauth_flow_session_key)
    |> put_resp_cookie("session", session_cookie,
      http_only: true,
      secure: true,
      same_site: "Lax",
      max_age: 60 * 60 * 24 * 14
    )
    |> redirect(to: "/")
  end
end
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
