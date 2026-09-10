defmodule Fireauth.OobCode.IdentityToolkit do
  @moduledoc false

  @behaviour Fireauth.OobCode

  alias Fireauth.IdentityToolkit.Client
  alias Fireauth.OobCode.Result

  @impl true
  @spec check(String.t(), keyword()) :: {:ok, Result.t()} | {:error, term()}
  def check(oob_code, opts) when is_binary(oob_code) and is_list(opts) do
    # `accounts:resetPassword` without a new password reports what a code is
    # for, whatever its type, and leaves it unspent.
    with {:ok, code} <- normalize_code(oob_code),
         {:ok, api_key} <- Client.fetch_api_key(opts),
         {:ok, %{} = response} <-
           Client.post("accounts:resetPassword", api_key, %{"oobCode" => code}, opts) do
      {:ok, build_result(response)}
    end
  end

  @impl true
  @spec apply_code(String.t(), keyword()) :: {:ok, Result.t()} | {:error, term()}
  def apply_code(oob_code, opts) when is_binary(oob_code) and is_list(opts) do
    with {:ok, code} <- normalize_code(oob_code),
         {:ok, api_key} <- Client.fetch_api_key(opts),
         {:ok, %{} = response} <-
           Client.post("accounts:update", api_key, %{"oobCode" => code}, opts) do
      {:ok, build_result(response)}
    end
  end

  defp build_result(response) do
    %Result{
      operation: operation(response["requestType"]),
      email: Client.blank_to_nil(response["email"] || ""),
      new_email: Client.blank_to_nil(response["newEmail"] || ""),
      raw_response: response
    }
  end

  defp operation("VERIFY_EMAIL"), do: :verify_email
  defp operation("PASSWORD_RESET"), do: :password_reset
  defp operation("RECOVER_EMAIL"), do: :recover_email
  defp operation("VERIFY_AND_CHANGE_EMAIL"), do: :verify_and_change_email
  defp operation("EMAIL_SIGNIN"), do: :email_signin
  defp operation(request_type) when is_binary(request_type), do: {:unknown, request_type}
  defp operation(_request_type), do: nil

  defp normalize_code(oob_code) do
    case String.trim(oob_code) do
      "" -> {:error, :invalid_oob_code}
      code -> {:ok, code}
    end
  end
end
