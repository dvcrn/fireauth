defmodule Fireauth do
  @moduledoc """
  Fireauth is a small library for Firebase Auth integration:

  - `Fireauth.Firebase` verifies Firebase SecureToken ID tokens.
  - `Fireauth.Plug` optionally attaches verified claims to `conn.assigns`
    and serves self-hosted Firebase auth helper files at `/__/auth/*`.
  """
end

