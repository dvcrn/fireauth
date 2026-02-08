defmodule Fireauth.TokenVerificationTest do
  use ExUnit.Case

  alias Fireauth.FirebaseUpstream.SecureTokenPublicKeys

  setup do
    :ok
  end

  test "verifies a correctly signed RS256 token using injected public key" do
    {kid, token} = build_rs256_token(project_id: "test-proj")

    # Inject a keyset containing the public key for kid.
    SecureTokenPublicKeys.put_keys(%{kid => public_pem_for_token(token)}, 3600)

    assert {:ok, claims} = Fireauth.verify_id_token(token, project_id: "test-proj")
    assert claims.aud == "test-proj"
    assert claims.iss == "https://securetoken.google.com/test-proj"
    assert is_binary(claims.sub) and claims.sub != ""
  end

  test "rejects invalid audience" do
    {kid, token} = build_rs256_token(project_id: "proj-a")
    SecureTokenPublicKeys.put_keys(%{kid => public_pem_for_token(token)}, 3600)

    assert {:error, :invalid_audience} = Fireauth.verify_id_token(token, project_id: "proj-b")
  end

  test "rejects non-RS256 alg before signature verification" do
    now = System.system_time(:second)

    claims = %{
      "aud" => "test-proj",
      "iss" => "https://securetoken.google.com/test-proj",
      "sub" => "uid",
      "exp" => now + 3600,
      "iat" => now - 10,
      "auth_time" => now - 10
    }

    jwk = JOSE.JWK.generate_key({:oct, 32})

    {_, token} =
      JOSE.JWT.sign(jwk, %{"alg" => "HS256", "kid" => "kid"}, claims) |> JOSE.JWS.compact()

    assert {:error, :invalid_alg} = Fireauth.verify_id_token(token, project_id: "test-proj")
  end

  defp build_rs256_token(opts) do
    project_id = Keyword.fetch!(opts, :project_id)
    now = System.system_time(:second)

    claims = %{
      "aud" => project_id,
      "iss" => "https://securetoken.google.com/#{project_id}",
      "sub" => "uid-" <> Integer.to_string(:rand.uniform(1_000_000)),
      "exp" => now + 3600,
      "iat" => now - 10,
      "auth_time" => now - 10,
      "user_id" => "uid"
    }

    kid = "test-kid-" <> Integer.to_string(:rand.uniform(1_000_000))
    jwk = JOSE.JWK.generate_key({:rsa, 2048})

    {_, token} =
      JOSE.JWT.sign(jwk, %{"alg" => "RS256", "kid" => kid}, claims) |> JOSE.JWS.compact()

    # Stash the private key in the process dictionary so we can derive public pem later.
    Process.put({__MODULE__, :last_jwk}, jwk)
    {kid, token}
  end

  defp public_pem_for_token(_token) do
    jwk = Process.get({__MODULE__, :last_jwk})
    jwk_pub = JOSE.JWK.to_public(jwk)
    {_fields, pem} = JOSE.JWK.to_pem(jwk_pub)
    pem
  end
end
