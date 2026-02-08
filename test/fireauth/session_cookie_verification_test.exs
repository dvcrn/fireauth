defmodule Fireauth.SessionCookieVerificationTest do
  use ExUnit.Case

  alias Fireauth.FirebaseUpstream.IdentityToolkitPublicKeys

  test "verifies a correctly signed RS256 session cookie using injected public key" do
    {kid, cookie} = build_rs256_cookie(project_id: "test-proj")

    IdentityToolkitPublicKeys.put_keys(%{kid => public_pem_for_cookie(cookie)}, 3600)

    assert {:ok, claims} = Fireauth.verify_session_cookie(cookie, project_id: "test-proj")
    assert claims.aud == "test-proj"
    assert claims.iss == "https://session.firebase.google.com/test-proj"
    assert is_binary(claims.sub) and claims.sub != ""
  end

  test "rejects invalid issuer" do
    now = System.system_time(:second)

    claims = %{
      "aud" => "test-proj",
      "iss" => "https://securetoken.google.com/test-proj",
      "sub" => "uid",
      "exp" => now + 3600,
      "iat" => now - 10,
      "auth_time" => now - 10
    }

    kid = "test-kid-" <> Integer.to_string(:rand.uniform(1_000_000))
    jwk = JOSE.JWK.generate_key({:rsa, 2048})

    {_, cookie} =
      JOSE.JWT.sign(jwk, %{"alg" => "RS256", "kid" => kid}, claims) |> JOSE.JWS.compact()

    jwk_pub = JOSE.JWK.to_public(jwk)
    {_fields, pem} = JOSE.JWK.to_pem(jwk_pub)
    IdentityToolkitPublicKeys.put_keys(%{kid => pem}, 3600)

    assert {:error, :invalid_issuer} =
             Fireauth.verify_session_cookie(cookie, project_id: "test-proj")
  end

  defp build_rs256_cookie(opts) do
    project_id = Keyword.fetch!(opts, :project_id)
    now = System.system_time(:second)

    claims = %{
      "aud" => project_id,
      "iss" => "https://session.firebase.google.com/#{project_id}",
      "sub" => "uid-" <> Integer.to_string(:rand.uniform(1_000_000)),
      "exp" => now + 3600,
      "iat" => now - 10,
      "auth_time" => now - 10,
      "user_id" => "uid"
    }

    kid = "test-kid-" <> Integer.to_string(:rand.uniform(1_000_000))
    jwk = JOSE.JWK.generate_key({:rsa, 2048})

    {_, cookie} =
      JOSE.JWT.sign(jwk, %{"alg" => "RS256", "kid" => kid}, claims) |> JOSE.JWS.compact()

    Process.put({__MODULE__, :last_jwk}, jwk)
    {kid, cookie}
  end

  defp public_pem_for_cookie(_cookie) do
    jwk = Process.get({__MODULE__, :last_jwk})
    jwk_pub = JOSE.JWK.to_public(jwk)
    {_fields, pem} = JOSE.JWK.to_pem(jwk_pub)
    pem
  end
end
