defmodule Fireauth.Account do
  @moduledoc """
  Firebase account management operations via Identity Toolkit.
  """

  @type opts :: keyword()

  @callback unlink_provider(String.t(), String.t(), opts()) :: {:ok, map()} | {:error, term()}

  @doc """
  Remove a provider from a Firebase user via Identity Toolkit `accounts:update`.

  Requires an ID token for the user whose provider should be removed.
  """
  @spec unlink_provider(String.t(), String.t(), opts()) :: {:ok, map()} | {:error, term()}
  def unlink_provider(id_token, provider_id, opts \\ [])
      when is_binary(id_token) and is_binary(provider_id) and is_list(opts) do
    adapter().unlink_provider(id_token, provider_id, opts)
  end

  defp adapter do
    Application.get_env(
      :fireauth,
      :account_adapter,
      Fireauth.Account.IdentityToolkit
    )
  end
end
