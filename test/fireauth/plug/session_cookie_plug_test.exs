defmodule Fireauth.Plug.SessionCookiePlugTest do
  use ExUnit.Case
  use Plug.Test

  alias Fireauth.FirebaseUpstream.IdentityToolkitPublicKeys
  alias Fireauth.Plug.SessionCookie, as: SessionCookiePlug

  test "assigns verified claims when session cookie is present" do
    {kid, cookie} = build_rs256_cookie(project_id: "test-proj")
    IdentityToolkitPublicKeys.put_keys(%{kid => public_pem_for_cookie()}, 3600)

    conn =
      conn(:get, "/")
      |> put_req_cookie("session", cookie)
      |> SessionCookiePlug.call(SessionCookiePlug.init(project_id: "test-proj"))

    assert conn.assigns.fireauth.token == cookie
    assert conn.assigns.fireauth.claims.iss == "https://session.firebase.google.com/test-proj"
    assert %Fireauth.User{} = conn.assigns.fireauth.user_attrs
  end

  test "on_invalid_cookie :unauthorized returns 401" do
    conn =
      conn(:get, "/")
      |> put_req_cookie("session", "not-a-jwt")
      |> SessionCookiePlug.call(
        SessionCookiePlug.init(project_id: "test-proj", on_invalid_cookie: :unauthorized)
      )

    assert conn.halted
    assert conn.status == 401
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

    jwk_pub = JOSE.JWK.to_public(jwk)
    {_fields, pem} = JOSE.JWK.to_pem(jwk_pub)
    Process.put({__MODULE__, :pem}, pem)

    {_, cookie} =
      JOSE.JWT.sign(jwk, %{"alg" => "RS256", "kid" => kid}, claims) |> JOSE.JWS.compact()

    {kid, cookie}
  end

  defp public_pem_for_cookie do
    Process.get({__MODULE__, :pem})
  end
end
