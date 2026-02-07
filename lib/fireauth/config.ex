defmodule Fireauth.Config do
  @moduledoc false

  @default_otp_app :fireauth

  @spec otp_app(keyword()) :: atom()
  def otp_app(opts) when is_list(opts) do
    Keyword.get(opts, :otp_app, @default_otp_app)
  end

  @spec firebase_project_id(keyword()) :: String.t() | nil
  def firebase_project_id(opts \\ []) when is_list(opts) do
    cond do
      is_binary(Keyword.get(opts, :project_id)) and Keyword.get(opts, :project_id) != "" ->
        Keyword.get(opts, :project_id)

      true ->
        otp_app = otp_app(opts)
        Application.get_env(otp_app, :firebase_project_id) || System.get_env("FIREBASE_PROJECT_ID")
    end
  end
end

