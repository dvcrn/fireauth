defmodule Fireauth.EmailLinkSenderTest do
  use ExUnit.Case, async: true

  import Mox

  alias Fireauth.EmailLinkSender.Result

  setup :verify_on_exit!

  setup do
    previous = Application.get_env(:fireauth, :email_link_sender_adapter)
    Application.put_env(:fireauth, :email_link_sender_adapter, Fireauth.EmailLinkSenderMock)

    on_exit(fn ->
      if previous do
        Application.put_env(:fireauth, :email_link_sender_adapter, previous)
      else
        Application.delete_env(:fireauth, :email_link_sender_adapter)
      end
    end)

    :ok
  end

  test "send_email_sign_in_link/3 delegates to the configured adapter" do
    expect(Fireauth.EmailLinkSenderMock, :send_sign_in_link, fn email, continue_url, opts ->
      assert email == "auth@example.com"
      assert continue_url == "https://www.example.com/auth/firebase/verify?return_to=%2F"
      assert opts[:otp_app] == :demo

      {:ok,
       %Result{
         email: email,
         raw_response: %{"email" => email}
       }}
    end)

    assert {:ok, %Result{email: "auth@example.com"}} =
             Fireauth.send_email_sign_in_link(
               "auth@example.com",
               "https://www.example.com/auth/firebase/verify?return_to=%2F",
               otp_app: :demo
             )
  end
end
