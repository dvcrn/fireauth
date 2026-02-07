defmodule Fireauth.FirebaseTest do
  use ExUnit.Case

  alias Fireauth.Firebase

  test "verify_id_token/2 rejects non-JWT tokens" do
    assert {:error, :invalid_token_format} = Fireauth.verify_id_token("nope")
    assert {:error, :invalid_token_format} = Fireauth.verify_id_token("a.b")
    assert {:error, :invalid_token_format} = Fireauth.verify_id_token("a.b.c.d")
  end

  test "claims_to_user_attrs/1 extracts expected fields" do
    claims = %{
      "sub" => "firebase-uid",
      "email" => "a@example.com",
      "picture" => "https://example.com/a.png",
      "firebase" => %{
        "sign_in_provider" => "github.com",
        "identities" => %{"github.com" => ["123"], "google.com" => ["456"]}
      }
    }

    attrs = Firebase.claims_to_user_attrs(claims)
    assert attrs.firebase_uid == "firebase-uid"
    assert attrs.email == "a@example.com"
    assert attrs.github_uid == "123"
    assert attrs.google_uid == "456"
    assert attrs.provider_uid == "123"
  end
end
