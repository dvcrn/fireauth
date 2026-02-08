defmodule FireauthTest do
  use ExUnit.Case

  alias Fireauth.Claims
  alias Fireauth.User

  describe "identity helpers" do
    setup do
      identities = %{"google.com" => ["google-uid"], "password" => ["email@example.com"]}
      claims = %Claims{identities: identities, user_id: "uid"}
      user = User.from_claims(claims)
      {:ok, claims: claims, user: user}
    end

    test "has_identity?/2 works with Claims and User", %{claims: claims, user: user} do
      assert Fireauth.has_identity?(claims, "google.com")
      assert Fireauth.has_identity?(user, "google.com")
      assert Fireauth.has_identity?(claims, :password)
      assert Fireauth.has_identity?(user, :password)

      refute Fireauth.has_identity?(claims, "github.com")
      refute Fireauth.has_identity?(user, "github.com")
    end

    test "has_identity?/2 handles nil identities" do
      data = %{identities: nil}
      refute Fireauth.has_identity?(data, "google.com")
    end

    test "get_identity/2 works with Claims and User", %{claims: claims, user: user} do
      assert Fireauth.get_identity(claims, "google.com") == "google-uid"
      assert Fireauth.get_identity(user, "google.com") == "google-uid"
      assert Fireauth.get_identity(claims, :password) == "email@example.com"
      assert Fireauth.get_identity(user, :password) == "email@example.com"

      assert Fireauth.get_identity(claims, "github.com") == nil
      assert Fireauth.get_identity(user, "github.com") == nil
    end

    test "get_identity/2 handles nil identities" do
      data = %{identities: nil}
      assert Fireauth.get_identity(data, "google.com") == nil
    end
  end
end
