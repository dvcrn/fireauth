# Fireauth

Firebase Auth helpers for Elixir apps:

- Verify Firebase ID tokens (RS256) using Google's SecureToken x509 certs.
- Optional Plug middleware that:
  - Proxies or serves Firebase auth helper files at `/__/auth/*` and `/__/firebase/init.json` to support redirect-based auth on your own domain.
  - Validates `Authorization: Bearer <id_token>` and attaches `%Fireauth.Claims{}` and `%Fireauth.User{}` to `conn.assigns`.

## Configuration

Add to your mix.exs

```
{:fireauth, "~> 0.1.1"},
```

Set your Firebase project id:

```elixir
config :fireauth, firebase_project_id: "your-project-id"
```

Or via env var: `FIREBASE_PROJECT_ID`.

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

### Plug Integration

Add `Fireauth.Plug` to your pipeline. It handles both auth file proxying and token verification.

```elixir
defmodule MyRouter do
  use Plug.Router

  plug :match

  plug Fireauth.Plug,
    project_id: "your-project-id",
    # :proxy (default) fetches from firebaseapp.com. :static serves local copies.
    hosted_auth_mode: :proxy,
    # :unauthorized returns 401. :ignore (default) just skips assignment.
    on_invalid_token: :unauthorized

  plug :dispatch

  get "/protected" do
    # Read derived user or raw claims from assigns
    %{user_attrs: user, claims: claims} = conn.assigns.fireauth

    send_resp(conn, 200, "Welcome #{user.email}")
  end
end
```

### Hosted Auth Modes

To support redirect-mode auth in modern browsers (avoiding third-party cookie issues), you must serve Firebase's helper files from your own domain.

1. **`:proxy` (Default):** Transparently proxies requests to `https://<project>.firebaseapp.com`. This is the most robust method. Responses are cached in-memory.
2. **`:static`:** Serves local copies of the helper files embedded in the `fireauth` library. Use this if your environment cannot make outbound requests to Firebase at runtime.

### Caching

This library caches all `/__/auth/*` calls in addition to the Google public key

## License

MIT
