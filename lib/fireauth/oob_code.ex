defmodule Fireauth.OobCode do
  @moduledoc """
  Inspect and apply the one-time codes Firebase puts in its action emails.

  Firebase's email templates link to an action handler with an `oobCode` query
  parameter. Applying that code is what verifies an address or confirms an email
  change; hosting the page yourself means making these calls yourself.

  `check/2` reads a code without spending it, so a page can name the address it
  is about before the user commits. `apply_code/2` spends it, and codes are
  single use: apply them from a user action rather than on page load, or link
  scanners will consume them before the recipient clicks.
  """

  alias Fireauth.OobCode.Result

  @type oob_code :: String.t()
  @type opts :: keyword()

  @callback check(oob_code(), opts()) :: {:ok, Result.t()} | {:error, term()}
  @callback apply_code(oob_code(), opts()) :: {:ok, Result.t()} | {:error, term()}

  @doc """
  Read what an `oobCode` is for without consuming it.
  """
  @spec check(oob_code(), opts()) :: {:ok, Result.t()} | {:error, term()}
  def check(oob_code, opts \\ []) when is_binary(oob_code) and is_list(opts) do
    adapter().check(oob_code, opts)
  end

  @doc """
  Apply an `oobCode`, verifying the address or confirming the email change it
  was issued for.

  Password reset codes are not applied here: confirming one needs a new
  password alongside the code.
  """
  @spec apply_code(oob_code(), opts()) :: {:ok, Result.t()} | {:error, term()}
  def apply_code(oob_code, opts \\ []) when is_binary(oob_code) and is_list(opts) do
    adapter().apply_code(oob_code, opts)
  end

  defp adapter do
    Application.get_env(:fireauth, :oob_code_adapter, Fireauth.OobCode.IdentityToolkit)
  end
end
