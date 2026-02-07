# Fireauth

Firebase Auth helpers for Elixir apps:

- Verify Firebase ID tokens (RS256) using Google's SecureToken x509 certs
- Optional Plug middleware that:
  - Proxies Firebase hosted auth helper files at `GET /__/auth/*` and `GET /__/firebase/init.json`
    (transparent reverse proxy to `https://<project>.firebaseapp.com`)
  - Validates `Authorization: Bearer <id_token>` (if present) and attaches claims to `conn.assigns`

## Configuration

Set your Firebase project id:

```elixir
config :fireauth, firebase_project_id: "your-project-id"
```

Or via env var: `FIREBASE_PROJECT_ID`.

Token validation uses an adapter (default `Fireauth.FirebaseTokenValidator`):

```elixir
config :fireauth, :token_validator_adapter, Fireauth.FirebaseTokenValidator
```

On application start, `:fireauth` will prefetch Google's SecureToken public keys
and log download status. You can disable the prefetch with:

```elixir
config :fireauth, :prefetch_public_keys, false
```

## Usage

Verify a token:

```elixir
{:ok, claims} = Fireauth.verify_id_token(id_token)
attrs = Fireauth.claims_to_user_attrs(claims)
```

Plug into a Phoenix endpoint (before `Plug.Static`):

```elixir
plug Fireauth.Plug
plug Plug.Static, ...
```

Then read:

- `conn.assigns.fireauth.claims`
- `conn.assigns.fireauth.user_attrs`
