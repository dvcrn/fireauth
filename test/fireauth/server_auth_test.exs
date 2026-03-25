defmodule Fireauth.ServerAuthTest do
  use ExUnit.Case, async: true

  import Mox

  alias Fireauth.ServerAuth.{SignInResult, StartResult}

  setup :verify_on_exit!

  setup do
    previous = Application.get_env(:fireauth, :server_auth_adapter)
    Application.put_env(:fireauth, :server_auth_adapter, Fireauth.ServerAuthMock)

    on_exit(fn ->
      if previous do
        Application.put_env(:fireauth, :server_auth_adapter, previous)
      else
        Application.delete_env(:fireauth, :server_auth_adapter)
      end
    end)

    :ok
  end

  test "start_oauth_sign_in/3 delegates to the configured adapter" do
    expect(Fireauth.ServerAuthMock, :start_oauth_sign_in, fn "google.com", callback_uri, opts ->
      assert callback_uri == "https://www.example.com/auth/firebase/callback/google"
      assert opts[:otp_app] == :demo

      {:ok,
       %StartResult{
         provider_id: "google.com",
         auth_uri: "https://accounts.google.com/o/oauth2/v2/auth",
         session_id: "session-123",
         raw_response: %{}
       }}
    end)

    assert {:ok, %StartResult{session_id: "session-123"}} =
             Fireauth.start_oauth_sign_in(
               "google.com",
               "https://www.example.com/auth/firebase/callback/google",
               otp_app: :demo
             )
  end

  test "finish_oauth_sign_in/4 delegates to the configured adapter" do
    expect(Fireauth.ServerAuthMock, :finish_oauth_sign_in, fn request_uri,
                                                              session_id,
                                                              post_body,
                                                              opts ->
      assert request_uri == "https://www.example.com/auth/firebase/callback/google?code=abc"
      assert session_id == "session-123"
      assert post_body == nil
      assert opts[:otp_app] == :demo

      {:ok,
       %SignInResult{
         provider_id: "google.com",
         firebase_id_token: "firebase-id-token",
         raw_response: %{}
       }}
    end)

    assert {:ok, %SignInResult{firebase_id_token: "firebase-id-token"}} =
             Fireauth.finish_oauth_sign_in(
               "https://www.example.com/auth/firebase/callback/google?code=abc",
               "session-123",
               nil,
               otp_app: :demo
             )
  end
end
