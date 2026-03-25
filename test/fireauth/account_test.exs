defmodule Fireauth.AccountTest do
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!

  setup do
    previous = Application.get_env(:fireauth, :account_adapter)
    Application.put_env(:fireauth, :account_adapter, Fireauth.AccountMock)

    on_exit(fn ->
      if previous do
        Application.put_env(:fireauth, :account_adapter, previous)
      else
        Application.delete_env(:fireauth, :account_adapter)
      end
    end)

    :ok
  end

  test "unlink_provider/3 delegates to the configured adapter" do
    expect(Fireauth.AccountMock, :unlink_provider, fn id_token, provider_id, opts ->
      assert id_token == "firebase-id-token"
      assert provider_id == "google.com"
      assert opts[:otp_app] == :demo

      {:ok, %{"localId" => "user-123"}}
    end)

    assert {:ok, %{"localId" => "user-123"}} =
             Fireauth.unlink_provider("firebase-id-token", "google.com", otp_app: :demo)
  end
end
