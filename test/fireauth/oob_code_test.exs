defmodule Fireauth.OobCodeTest do
  use ExUnit.Case, async: true

  import Mox

  alias Fireauth.OobCode
  alias Fireauth.OobCode.Result

  setup :verify_on_exit!

  describe "facade" do
    setup do
      Application.put_env(:fireauth, :oob_code_adapter, Fireauth.OobCodeMock)
      on_exit(fn -> Application.delete_env(:fireauth, :oob_code_adapter) end)
      :ok
    end

    test "check_oob_code/2 delegates to the configured adapter" do
      expect(Fireauth.OobCodeMock, :check, fn "code-123", opts ->
        assert opts[:otp_app] == :demo
        {:ok, %Result{operation: :verify_email, email: "user@example.com", raw_response: %{}}}
      end)

      assert {:ok, %Result{operation: :verify_email, email: "user@example.com"}} =
               Fireauth.check_oob_code("code-123", otp_app: :demo)
    end

    test "apply_oob_code/2 delegates to the configured adapter" do
      expect(Fireauth.OobCodeMock, :apply_code, fn "code-123", _opts ->
        {:ok, %Result{operation: :verify_email, email: "user@example.com", raw_response: %{}}}
      end)

      assert {:ok, %Result{email: "user@example.com"}} = Fireauth.apply_oob_code("code-123")
    end
  end

  describe "identity toolkit adapter" do
    test "check/2 reports the operation without consuming the code" do
      opts = [firebase_api_key: "test-key", req_options: [plug: &respond(&1, "VERIFY_EMAIL")]]

      assert {:ok, %Result{operation: :verify_email, email: "user@example.com"}} =
               OobCode.check("code-123", opts)
    end

    test "check/2 maps unknown request types" do
      opts = [firebase_api_key: "test-key", req_options: [plug: &respond(&1, "SOMETHING_NEW")]]

      assert {:ok, %Result{operation: {:unknown, "SOMETHING_NEW"}}} =
               OobCode.check("code-123", opts)
    end

    test "apply_code/2 posts the code to accounts:update" do
      opts = [firebase_api_key: "test-key", req_options: [plug: &respond(&1, nil)]]

      assert {:ok, %Result{email: "user@example.com"}} = OobCode.apply_code("code-123", opts)
    end

    test "rejects a blank code before calling out" do
      assert {:error, :invalid_oob_code} = OobCode.check("   ", [])
    end

    test "surfaces identity toolkit errors" do
      plug = fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(400, ~s({"error": {"message": "EXPIRED_OOB_CODE"}}))
      end

      assert {:error, {:identity_toolkit_error, path, 400, body}} =
               OobCode.check("code-123", firebase_api_key: "test-key", req_options: [plug: plug])

      assert path == "accounts:resetPassword"
      assert body["error"]["message"] == "EXPIRED_OOB_CODE"
    end
  end

  defp respond(conn, request_type) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    assert Jason.decode!(body) == %{"oobCode" => "code-123"}

    assert conn.request_path =~
             if(request_type, do: "accounts:resetPassword", else: "accounts:update")

    response =
      %{"email" => "user@example.com", "requestType" => request_type}
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(200, Jason.encode!(response))
  end
end
