defmodule Fireauth.UserTest do
  use ExUnit.Case

  alias Fireauth.Claims
  alias Fireauth.User

  test "from_claims/1 extracts expected fields" do
    claims = %Claims{
      user_id: "firebase-uid",
      email: "a@example.com",
      name: "Alice",
      picture: "https://example.com/a.png",
      sign_in_provider: "github.com",
      identities: %{"github.com" => ["123"], "google.com" => ["456"]}
    }

    user = User.from_claims(claims)

    assert %User{} = user
    assert user.firebase_uid == "firebase-uid"
    assert user.email == "a@example.com"
    assert user.name == "Alice"
    assert user.avatar_url == "https://example.com/a.png"
    assert user.identities["github.com"] == ["123"]
    assert user.identities["google.com"] == ["456"]
    assert user.sign_in_provider == "github.com"
  end

  test "from_claims/1 handles missing optional fields" do
    claims = %Claims{
      user_id: "uid-only",
      identities: %{}
    }

    user = User.from_claims(claims)
    assert user.firebase_uid == "uid-only"
    assert user.email == nil
    assert user.name == nil
    assert user.identities == nil
  end
end
