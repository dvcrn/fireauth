defmodule Fireauth.Config do
  @moduledoc false

  @default_otp_app :fireauth

  alias Fireauth.Admin.ServiceAccount

  @type service_account :: map()

  @spec otp_app(keyword()) :: atom()
  def otp_app(opts) when is_list(opts) do
    Keyword.get(opts, :otp_app, @default_otp_app)
  end

  @spec firebase_project_id(keyword()) :: String.t() | nil

  def firebase_project_id(opts \\ []) when is_list(opts) do
    if is_binary(Keyword.get(opts, :project_id)) and Keyword.get(opts, :project_id) != "" do
      Keyword.get(opts, :project_id)
    else
      otp_app = otp_app(opts)

      Application.get_env(otp_app, :firebase_project_id) || System.get_env("FIREBASE_PROJECT_ID")
    end
  end

  @spec firebase_admin_service_account(keyword()) :: service_account() | nil
  def firebase_admin_service_account(opts \\ []) when is_list(opts) do
    otp_app = otp_app(opts)

    value =
      Keyword.get(opts, :firebase_admin_service_account) ||
        Application.get_env(otp_app, :firebase_admin_service_account) ||
        System.get_env("FIREBASE_ADMIN_SERVICE_ACCOUNT")

    case ServiceAccount.decode(value) do
      {:ok, sa} -> sa
      {:error, _reason} -> nil
    end
  end
end
