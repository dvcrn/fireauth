defmodule Fireauth.Config do
  @moduledoc false

  @default_otp_app :fireauth

  alias Fireauth.Admin.ServiceAccount

  @type service_account :: map()
  @type firebase_web_config :: map()

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

  @spec firebase_web_config(keyword()) :: firebase_web_config() | nil
  def firebase_web_config(opts \\ []) when is_list(opts) do
    otp_app = otp_app(opts)

    cfg =
      Keyword.get(opts, :firebase_web_config) ||
        Application.get_env(otp_app, :firebase_web_config) ||
        default_web_config_from_env()

    if is_map(cfg) do
      cfg
    else
      nil
    end
  end

  defp default_web_config_from_env do
    %{
      "apiKey" => System.get_env("FIREBASE_API_KEY"),
      "authDomain" => System.get_env("FIREBASE_AUTH_DOMAIN"),
      "projectId" => System.get_env("FIREBASE_PROJECT_ID"),
      "storageBucket" => System.get_env("FIREBASE_STORAGE_BUCKET"),
      "messagingSenderId" => System.get_env("FIREBASE_MESSAGING_SENDER_ID"),
      "appId" => System.get_env("FIREBASE_APP_ID")
    }
  end
end
