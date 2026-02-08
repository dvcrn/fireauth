defmodule Fireauth.AdminServiceAccountTest do
  use ExUnit.Case

  alias Fireauth.Admin.OAuth
  alias Fireauth.Admin.ServiceAccount

  test "ServiceAccount.decode/1 accepts map" do
    assert {:ok, sa} = ServiceAccount.decode(%{"client_email" => "x", "private_key" => "y"})
    assert sa["client_email"] == "x"
  end

  test "ServiceAccount.decode/1 accepts JSON" do
    json = ~s({"client_email":"x","private_key":"y","project_id":"p"})
    assert {:ok, sa} = ServiceAccount.decode(json)
    assert sa["project_id"] == "p"
  end

  test "ServiceAccount.decode/1 accepts base64 JSON" do
    json = ~s({"client_email":"x","private_key":"y","project_id":"p"})
    b64 = Base.encode64(json)
    assert {:ok, sa} = ServiceAccount.decode(b64)
    assert sa["client_email"] == "x"
  end

  test "OAuth.build_assertion/4 builds a JWT with expected claims" do
    client_email = "svc@example.iam.gserviceaccount.com"
    token_uri = "https://oauth2.googleapis.com/token"
    scope = "https://www.googleapis.com/auth/identitytoolkit"

    jwk = JOSE.JWK.generate_key({:rsa, 2048})
    {_fields, pem} = JOSE.JWK.to_pem(jwk)

    assert {:ok, assertion} = OAuth.build_assertion(client_email, pem, token_uri, scope)
    assert length(String.split(assertion, ".", parts: 4)) == 3

    jwt = JOSE.JWT.peek_payload(assertion)
    claims = jwt.fields
    assert claims["iss"] == client_email
    assert claims["sub"] == client_email
    assert claims["aud"] == token_uri
    assert claims["scope"] == scope
    assert is_integer(claims["iat"])
    assert is_integer(claims["exp"])
    assert claims["exp"] > claims["iat"]
  end
end
