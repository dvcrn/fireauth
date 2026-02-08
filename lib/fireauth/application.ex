defmodule Fireauth.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Fireauth.FirebaseUpstream.SecureTokenPublicKeys, []},
      {Fireauth.FirebaseUpstream.Cache, []}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Fireauth.Supervisor)
  end
end
