defmodule Fireauth.StructHelpersTest do
  use ExUnit.Case, async: true
  alias Fireauth

  describe "has_identity?/2 with Fireauth struct" do
    test "returns true if user has the identity" do
      user = %Fireauth.User{
        identities: %{"google.com" => ["123"], "email" => ["test@example.com"]}
      }

      fireauth = %Fireauth{user: user}

      assert Fireauth.has_identity?(fireauth, "google.com")
      assert Fireauth.has_identity?(fireauth, :email)
    end

    test "returns false if user does not have the identity" do
      user = %Fireauth.User{identities: %{"google.com" => ["123"]}}
      fireauth = %Fireauth{user: user}

      refute Fireauth.has_identity?(fireauth, "facebook.com")
    end

    test "returns false if user is nil" do
      fireauth = %Fireauth{user: nil}
      refute Fireauth.has_identity?(fireauth, "google.com")
    end
  end

  describe "identity/2 with Fireauth struct" do
    test "returns the identity ID if present" do
      user = %Fireauth.User{
        identities: %{"google.com" => ["123"], "email" => ["test@example.com"]}
      }

      fireauth = %Fireauth{user: user}

      assert Fireauth.identity(fireauth, "google.com") == "123"
      assert Fireauth.identity(fireauth, :email) == "test@example.com"
    end

    test "returns nil if identity is missing" do
      user = %Fireauth.User{identities: %{"google.com" => ["123"]}}
      fireauth = %Fireauth{user: user}

      assert Fireauth.identity(fireauth, "facebook.com") == nil
    end

    test "returns nil if user is nil" do
      fireauth = %Fireauth{user: nil}
      assert Fireauth.identity(fireauth, "google.com") == nil
    end
  end

  describe "identities/1" do
    test "returns the identities map from Fireauth struct" do
      user = %Fireauth.User{
        identities: %{"google.com" => ["123"], "email" => ["test@example.com"]}
      }

      fireauth = %Fireauth{user: user}

      assert Fireauth.identities(fireauth) == %{
               "google.com" => ["123"],
               "email" => ["test@example.com"]
             }
    end

    test "returns empty map if identities is nil or missing" do
      user = %Fireauth.User{identities: nil}
      fireauth = %Fireauth{user: user}

      assert Fireauth.identities(fireauth) == %{}
    end

    test "returns empty map if user is nil" do
      fireauth = %Fireauth{user: nil}
      assert Fireauth.identities(fireauth) == %{}
    end
  end
end
