# Fireauth Integration Guide for LLMs

This document is intended for LLMs. If you're a human, read the README instead.

This document captures a Fireauth redirect-flow integration that worked well in
a Phoenix application, including the adjustments that were needed beyond the
basic README examples.

Official reference:

- `https://github.com/dvcrn/fireauth/blob/main/README.md`

## Summary

Working shape:

- Firebase browser auth uses redirect flow, not popup flow
- `/login` only hosts the sign-in button or form
- `POST /auth/firebase/start` renders the redirect loading screen
- `GET /auth/firebase/start` is only the post-provider handoff and redirects to `/auth/firebase/verify`
- `/auth/firebase/verify` runs the ID token to session-cookie exchange
- Fireauth hosted callback files are mounted at the endpoint level
- Fireauth session-cookie endpoints are mounted outside the Phoenix browser pipeline
- the browser bundle only contains a thin Firebase bootstrap wrapper
- local redirect-mode development should use HTTPS

## Dependency

Use a Fireauth version that includes:

- `Fireauth.Plug`
- `Fireauth.Plug.SessionRouter`
- `Fireauth.Plug.SessionCookie`
- `Fireauth.Snippets.client/1`
- `Fireauth.HostedController`

Example:

```elixir
{:fireauth, "~> 0.5.0"}
```

## Required Configuration

### Firebase web config

The browser-side Firebase config must be available at runtime, either through
environment variables or application config.

Typical required values:

- `FIREBASE_API_KEY`
- `FIREBASE_AUTH_DOMAIN`
- `FIREBASE_PROJECT_ID`
- `FIREBASE_APP_ID`

Depending on the app, you may also set:

- `FIREBASE_STORAGE_BUCKET`
- `FIREBASE_MESSAGING_SENDER_ID`

### Firebase admin service account

Session-cookie minting requires a Firebase Admin service account.

Provide it through configuration or an environment variable such as:

- `FIREBASE_ADMIN_SERVICE_ACCOUNT`

Do not keep the raw JSON key checked into the repository.

## Router and Endpoint Setup

### 1. Mount hosted Firebase callback files at the endpoint

`Fireauth.Plug` must run at the endpoint level, before the router. If this is
only mounted in the router, Firebase helper paths like `"/__/auth/handler"`
will 404.

Example:

```elixir
plug Fireauth.Plug,
  otp_app: :my_app,
  callback_overrides: %{
    "/__/auth/handler" => Fireauth.HostedController,
    "/__/auth/iframe" => Fireauth.HostedController,
    "/__/auth/handler.js" => Fireauth.HostedController,
    "/__/auth/iframe.js" => Fireauth.HostedController,
    "/__/auth/experiments.js" => Fireauth.HostedController,
    "/__/firebase/init.json" => Fireauth.HostedController
  }
```

### 2. Verify Fireauth session cookies in the browser pipeline

Browser requests use:

```elixir
plug Fireauth.Plug.SessionCookie, otp_app: :my_app
```

This makes `conn.assigns.fireauth` available on server-rendered pages.

### 3. Mount Fireauth session endpoints outside the browser pipeline

This is critical:

```elixir
forward "/auth/firebase", Fireauth.Plug.SessionRouter,
  init_opts: [...]
```

Do not put that `forward` inside `pipe_through :browser`.

Reason:

- `Fireauth.Plug.SessionRouter` already does its own CSRF flow with `GET /csrf` then `POST /session`
- if the route goes through Phoenix `plug :protect_from_forgery`, Phoenix rejects the request before Fireauth can validate its own token

Observed failure when this was wrong:

- `POST /auth/firebase/session` returned `403`
- stacktrace showed `Plug.CSRFProtection.InvalidCSRFTokenError`
- logs showed the request going through `Pipelines: [:browser]`

Fix:

- move `forward "/auth/firebase"` out of the browser pipeline

## Thin Wrapper Rule

Keep the browser-side Firebase wrapper intentionally thin.

The correct split is:

- the root layout exposes a Firebase config object on `window`
- a small app JS file initializes Firebase once
- that JS file exposes a minimal `window.firebase.auth` surface
- the start and verify templates call `window.fireauth.start(...)` and `window.fireauth.verify(...)` directly

Avoid reintroducing:

- a large app-specific auth flow controller
- `sessionStorage` redirect bookkeeping
- shared JS that owns the redirect/verify state machine
- orchestration code that duplicates Fireauth behavior

Fireauth exists specifically so the application does not need that complexity.

## Login Flow

### Chosen flow

This setup uses Fireauth redirect flow:

1. Render a dedicated `/login` page
2. Submit a normal Phoenix form with `POST /auth/firebase/start?return_to=...`
3. Render `Fireauth.Snippets.client/1` on the start loading page
4. Call `window.fireauth.start(...)`
5. Call Firebase `signInWithRedirect(...)`
6. After the provider roundtrip, Firebase lands on `GET /auth/firebase/start`
7. That GET route immediately redirects to `/auth/firebase/verify`
8. Render `Fireauth.Snippets.client/1` on the verify loading page
9. Call `window.fireauth.verify(...)`
10. Fireauth exchanges the Firebase ID token for an `httpOnly` session cookie
11. Browser redirects to the final page

### Why not popup flow

The Fireauth README documents redirect-mode support with hosted auth files and
the client snippet helpers. Popup auth is not the shape this guide is designed
around.

The intended contract is:

- `Fireauth.Snippets.client/1`
- `window.fireauth.start(...)`
- `window.fireauth.verify(...)`
- Firebase `signInWithRedirect(...)`

## Extra Steps That Deviate From The Official Docs

### 1. Use a dedicated `/login` page plus two loading pages

The README shows generic examples, but a clean Phoenix shape is:

- `/login` hosts the sign-in form only
- `POST /auth/firebase/start` renders the redirect spinner page
- `GET /auth/firebase/start` is a handoff route, not a UI page
- `/auth/firebase/verify` renders the session-exchange spinner page

This keeps the normal login page clean and keeps redirect-specific UI on
dedicated loading screens.

### 2. Use `POST /auth/firebase/start` for the initial dispatch

The initial move into the redirect flow is a normal Phoenix form POST.

That helps because it lets the app:

- choose the provider explicitly
- carry `return_to`
- avoid adding custom client-side bookkeeping before redirect starts

After Firebase returns, `GET /auth/firebase/start` just redirects to verify.

### 3. `"/__/firebase/init.json"` may need to be served locally, not proxied

The README example shows:

```elixir
"/__/firebase/init.json" => Fireauth.ProxyController
```

In some Firebase Hosting setups that upstream path may return a real 404. In
that case, a working alternative is:

```elixir
"/__/firebase/init.json" => Fireauth.HostedController
```

That is a deliberate deviation based on runtime behavior, not just preference.

### 4. Rewrite `authDomain` to the current app host during HTTPS localhost dev

For local HTTPS redirect-mode flows, it can help to rewrite `authDomain` to
`window.location.host` when:

- host is `localhost` or `127.0.0.1`
- protocol is `https:`

This keeps the redirect flow on the first-party origin.

### 5. Local redirect-mode development should use HTTPS

If redirect-mode auth behaves inconsistently on localhost, switch local
development to HTTPS and authorize that host in Firebase.

Common local example:

- `https://localhost:<port>`

### 6. Fireauth session routes must stay outside Phoenix CSRF

This is the main Phoenix-specific adjustment.

Official docs tell you to mount `Fireauth.Plug.SessionRouter`, but in Phoenix
the placement matters:

- if it lives inside `:browser`, Phoenix CSRF blocks `POST /auth/firebase/session`
- if it lives outside `:browser`, Fireauth’s own CSRF flow works correctly

### 7. Keep logout separate from the login flow

Fireauth owns login start and verify. Logout remains a small app concern:

- optionally call Firebase `signOut(...)`
- POST to `"/auth/firebase/logout"`
- redirect to the login page

That logic should stay small and isolated.

## Firebase Console Requirements

If sign-in fails with:

- `auth/configuration-not-found`

check Firebase Console:

1. Authentication is enabled
2. The intended provider is enabled
3. The provider has any required support email or saved setup fields
4. The local development host is listed under Authorized domains

Important:

- use the same host consistently, for example `localhost` vs `127.0.0.1`
- the authorized domain must match the host actually used in the browser

## HTTPS Localhost

Local HTTPS is often required for this dev flow.

Notes:

- the local certificate may need to be trusted in the browser
- if the browser host changes, Firebase Authorized Domains must match

### Example Phoenix HTTPS config

For local Phoenix development, configure the endpoint to serve HTTPS with a
local certificate and key.

Example:

```elixir
# config/dev.exs
config :my_app, MyAppWeb.Endpoint,
  https: [
    ip: {127, 0, 0, 1},
    port: 4001,
    cipher_suite: :strong,
    keyfile: "priv/cert/selfsigned_key.pem",
    certfile: "priv/cert/selfsigned.pem"
  ],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev-only-secret"
```

Use whatever host and port match your app, but keep the Firebase authorized
domain and the browser URL aligned with that exact host.

In practice this usually means:

- generate or provide a local certificate and key
- run the app on `https://localhost:<port>` or `https://127.0.0.1:<port>`
- add that host to Firebase Authorized Domains

## Useful Checks

### Check Firebase init config

Open:

- `https://localhost:<port>/__/firebase/init.json`

Confirm it returns the expected project config.

### Expected request sequence during login

The working request sequence is:

1. `GET /login`
2. `POST /auth/firebase/start`
3. browser redirects to the provider
4. `GET /auth/firebase/start`
5. `302 -> /auth/firebase/verify`
6. `GET /auth/firebase/csrf`
7. `POST /auth/firebase/session`
8. `GET /final-page`

If step 7 returns `403`, the session router is probably still behind Phoenix
CSRF.

## Verification

After wiring the integration, run the app’s normal compile, asset build, and
test or lint steps.

At minimum, verify:

- the start page renders
- the provider redirect begins
- the verify page exchanges the token successfully
- the session cookie is set
- authenticated routes receive `conn.assigns.fireauth`
