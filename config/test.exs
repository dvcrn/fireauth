import Config

# Avoid network calls during tests. Tests can inject keys explicitly.
config :fireauth, prefetch_public_keys: false

