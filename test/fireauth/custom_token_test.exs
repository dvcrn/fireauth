defmodule Fireauth.CustomTokenTest do
  use ExUnit.Case, async: true

  alias Fireauth.CustomToken.Firebase, as: CustomTokenFirebase

  @audience "https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit"

  # Generate a throwaway RSA key for test signing
  @test_jwk JOSE.JWK.generate_key({:rsa, 2048})
  @test_pem JOSE.JWK.to_pem(@test_jwk) |> elem(1)

  @test_service_account %{
    "client_email" => "test@test-project.iam.gserviceaccount.com",
    "private_key" => @test_pem,
    "project_id" => "test-project"
  }

  setup do
    previous = Application.get_env(:fireauth, :firebase_admin_service_account)

    Application.put_env(:fireauth, :firebase_admin_service_account, @test_service_account)

    on_exit(fn ->
      if previous do
        Application.put_env(:fireauth, :firebase_admin_service_account, previous)
      else
        Application.delete_env(:fireauth, :firebase_admin_service_account)
      end
    end)

    :ok
  end

  describe "create_custom_token/2" do
    test "returns a valid JWT with required claims" do
      assert {:ok, token} = CustomTokenFirebase.create_custom_token("user-123")
      assert is_binary(token)

      # Decode and verify the token structure
      {_, payload} = JOSE.JWT.peek(token) |> Map.get(:fields) |> then(&{:ok, &1})

      assert payload["iss"] == "test@test-project.iam.gserviceaccount.com"
      assert payload["sub"] == "test@test-project.iam.gserviceaccount.com"
      assert payload["aud"] == @audience
      assert payload["uid"] == "user-123"
      assert is_integer(payload["iat"])
      assert is_integer(payload["exp"])
      assert payload["exp"] - payload["iat"] == 3600
    end

    test "includes additional claims when provided" do
      assert {:ok, token} =
               CustomTokenFirebase.create_custom_token("user-123",
                 claims: %{"role" => "admin"}
               )

      payload = JOSE.JWT.peek(token).fields

      assert payload["uid"] == "user-123"
      assert payload["claims"] == %{"role" => "admin"}
    end

    test "omits claims key when no additional claims" do
      assert {:ok, token} = CustomTokenFirebase.create_custom_token("user-123")

      payload = JOSE.JWT.peek(token).fields

      refute Map.has_key?(payload, "claims")
    end

    test "rejects empty uid" do
      assert {:error, :invalid_uid} = CustomTokenFirebase.create_custom_token("")
    end

    test "rejects uid longer than 128 characters" do
      long_uid = String.duplicate("a", 129)
      assert {:error, :invalid_uid} = CustomTokenFirebase.create_custom_token(long_uid)
    end

    test "accepts uid at exactly 128 characters" do
      uid = String.duplicate("a", 128)
      assert {:ok, _token} = CustomTokenFirebase.create_custom_token(uid)
    end

    test "returns error when service account is missing" do
      Application.delete_env(:fireauth, :firebase_admin_service_account)

      assert {:error, :missing_service_account} =
               CustomTokenFirebase.create_custom_token("user-123")
    end

    test "the token is verifiable with the signing key" do
      assert {:ok, token} = CustomTokenFirebase.create_custom_token("user-123")

      {verified, _jwt, _jws} = JOSE.JWT.verify(@test_jwk, token)
      assert verified
    end
  end

  describe "adapter delegation" do
    test "Fireauth.create_custom_token/2 delegates to the adapter" do
      # This test just ensures the facade works
      assert {:ok, _token} = Fireauth.create_custom_token("user-456")
    end

    test "Fireauth.exchange_custom_token/2 delegates to the configured adapter" do
      import Mox

      previous = Application.get_env(:fireauth, :custom_token_adapter)
      Application.put_env(:fireauth, :custom_token_adapter, Fireauth.CustomTokenMock)

      on_exit(fn ->
        if previous do
          Application.put_env(:fireauth, :custom_token_adapter, previous)
        else
          Application.delete_env(:fireauth, :custom_token_adapter)
        end
      end)

      expect(Fireauth.CustomTokenMock, :exchange_custom_token, fn token, opts ->
        assert token == "custom-token-jwt"
        assert opts[:otp_app] == :demo
        {:ok, "firebase-id-token"}
      end)

      assert {:ok, "firebase-id-token"} =
               Fireauth.exchange_custom_token("custom-token-jwt", otp_app: :demo)

      verify!()
    end
  end
end
