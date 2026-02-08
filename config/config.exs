import Config

config :fireauth,
  firebaseapp_domain: "firebaseapp.com"

import_config "#{config_env()}.exs"

