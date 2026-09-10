defmodule Fireauth.PasswordReset.IdentityToolkit do
  @moduledoc false

  @behaviour Fireauth.PasswordReset

  alias Fireauth.IdentityToolkit.Client
  alias Fireauth.PasswordReset.Result

  @impl true
  @spec send_email(String.t(), String.t() | nil, keyword()) ::
          {:ok, Result.t()} | {:error, term()}
  def send_email(email, continue_url, opts) when is_binary(email) and is_list(opts) do
    with {:ok, normalized_email} <- normalize_email(email),
         {:ok, api_key} <- Client.fetch_api_key(opts),
         {:ok, %{} = response} <-
           Client.post(
             "accounts:sendOobCode",
             api_key,
             build_request_body(normalized_email, continue_url, opts),
             opts
           ) do
      {:ok, %Result{email: response["email"] || normalized_email, raw_response: response}}
    end
  end

  @impl true
  @spec confirm(String.t(), String.t(), keyword()) :: {:ok, Result.t()} | {:error, term()}
  def confirm(oob_code, new_password, opts)
      when is_binary(oob_code) and is_binary(new_password) and is_list(opts) do
    with {:ok, code} <- normalize_code(oob_code),
         {:ok, password} <- normalize_password(new_password),
         {:ok, api_key} <- Client.fetch_api_key(opts),
         {:ok, %{} = response} <-
           Client.post(
             "accounts:resetPassword",
             api_key,
             %{"oobCode" => code, "newPassword" => password},
             opts
           ) do
      {:ok, %Result{email: Client.blank_to_nil(response["email"] || ""), raw_response: response}}
    end
  end

  defp build_request_body(email, continue_url, opts) do
    %{
      "requestType" => "PASSWORD_RESET",
      "email" => email,
      "continueUrl" => Client.blank_to_nil(continue_url || ""),
      "tenantId" => Client.blank_to_nil(Keyword.get(opts, :tenant_id))
    }
    |> Client.compact_map()
  end

  defp normalize_email(email) do
    case String.trim(email) do
      "" -> {:error, :invalid_email}
      normalized -> {:ok, normalized}
    end
  end

  defp normalize_code(oob_code) do
    case String.trim(oob_code) do
      "" -> {:error, :invalid_oob_code}
      code -> {:ok, code}
    end
  end

  defp normalize_password(new_password) do
    if new_password == "" do
      {:error, :invalid_password}
    else
      {:ok, new_password}
    end
  end
end
