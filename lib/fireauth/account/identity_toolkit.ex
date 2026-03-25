defmodule Fireauth.Account.IdentityToolkit do
  @moduledoc false

  @behaviour Fireauth.Account

  alias Fireauth.IdentityToolkit.Client

  @impl true
  @spec unlink_provider(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def unlink_provider(id_token, provider_id, opts \\ [])
      when is_binary(id_token) and is_binary(provider_id) and is_list(opts) do
    with {:ok, api_key} <- Client.fetch_api_key(opts) do
      Client.post(
        "accounts:update",
        api_key,
        %{"idToken" => id_token, "deleteProvider" => [provider_id]},
        opts
      )
    end
  end
end
