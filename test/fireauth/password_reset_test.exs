defmodule Fireauth.PasswordResetTest do
  use ExUnit.Case, async: true

  import Mox

  alias Fireauth.PasswordReset
  alias Fireauth.PasswordReset.Result

  setup :verify_on_exit!

  describe "facade" do
    setup do
      Application.put_env(:fireauth, :password_reset_adapter, Fireauth.PasswordResetMock)
      on_exit(fn -> Application.delete_env(:fireauth, :password_reset_adapter) end)
      :ok
    end

    test "send_password_reset_email/3 delegates to the configured adapter" do
      expect(Fireauth.PasswordResetMock, :send_email, fn email, continue_url, opts ->
        assert email == "user@example.com"
        assert continue_url == "https://www.example.com/auth/action"
        assert opts[:otp_app] == :demo

        {:ok, %Result{email: email, raw_response: %{}}}
      end)

      assert {:ok, %Result{email: "user@example.com"}} =
               Fireauth.send_password_reset_email(
                 "user@example.com",
                 "https://www.example.com/auth/action",
                 otp_app: :demo
               )
    end

    test "confirm_password_reset/3 delegates to the configured adapter" do
      expect(Fireauth.PasswordResetMock, :confirm, fn "code-123", "hunter22", _opts ->
        {:ok, %Result{email: "user@example.com", raw_response: %{}}}
      end)

      assert {:ok, %Result{email: "user@example.com"}} =
               Fireauth.confirm_password_reset("code-123", "hunter22")
    end
  end

  describe "identity toolkit adapter" do
    test "send_email/3 requests a PASSWORD_RESET code" do
      plug = fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        assert Jason.decode!(body) == %{
                 "requestType" => "PASSWORD_RESET",
                 "email" => "user@example.com",
                 "continueUrl" => "https://www.example.com/auth/action"
               }

        assert conn.request_path =~ "accounts:sendOobCode"
        json(conn, 200, %{"email" => "user@example.com"})
      end

      assert {:ok, %Result{email: "user@example.com"}} =
               PasswordReset.send_email(
                 "user@example.com",
                 "https://www.example.com/auth/action",
                 api_key: "test-key",
                 req_options: [plug: plug]
               )
    end

    test "send_email/3 omits an absent continue url" do
      plug = fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        refute Map.has_key?(Jason.decode!(body), "continueUrl")
        json(conn, 200, %{"email" => "user@example.com"})
      end

      assert {:ok, %Result{}} =
               PasswordReset.send_email("user@example.com", nil,
                 api_key: "test-key",
                 req_options: [plug: plug]
               )
    end

    test "confirm/3 posts the code and the new password" do
      plug = fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        assert Jason.decode!(body) == %{
                 "oobCode" => "code-123",
                 "newPassword" => "hunter22"
               }

        assert conn.request_path =~ "accounts:resetPassword"
        json(conn, 200, %{"email" => "user@example.com"})
      end

      assert {:ok, %Result{email: "user@example.com"}} =
               PasswordReset.confirm("code-123", "hunter22",
                 api_key: "test-key",
                 req_options: [plug: plug]
               )
    end

    test "rejects blank input before calling out" do
      assert {:error, :invalid_email} = PasswordReset.send_email("  ", nil, [])
      assert {:error, :invalid_oob_code} = PasswordReset.confirm(" ", "hunter22", [])
      assert {:error, :invalid_password} = PasswordReset.confirm("code-123", "", [])
    end

    test "surfaces a weak password rejection" do
      plug = fn conn -> json(conn, 400, %{"error" => %{"message" => "WEAK_PASSWORD"}}) end

      assert {:error, {:identity_toolkit_error, "accounts:resetPassword", 400, body}} =
               PasswordReset.confirm("code-123", "short",
                 api_key: "test-key",
                 req_options: [plug: plug]
               )

      assert body["error"]["message"] == "WEAK_PASSWORD"
    end
  end

  defp json(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end
end
