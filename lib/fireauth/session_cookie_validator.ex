defmodule Fireauth.SessionCookieValidator do
  @moduledoc false

  alias Fireauth.Claims
  alias Fireauth.Config
  alias Fireauth.FirebaseUpstream.IdentityToolkitPublicKeys

  @type session_cookie :: String.t()
  @type claims :: Claims.t()

  @spec verify_session_cookie(session_cookie(), keyword()) :: {:ok, claims()} | {:error, term()}
  def verify_session_cookie(cookie, opts \\ []) when is_binary(cookie) and is_list(opts) do
    if looks_like_jwt?(cookie) do
      do_verify_session_cookie(cookie, opts)
    else
      {:error, :invalid_cookie_format}
    end
  end

  defp do_verify_session_cookie(cookie, opts) do
    with {:ok, header} <- peek_header(cookie),
         :ok <- validate_header(header),
         {:ok, kid} <- fetch_kid(header),
         {:ok, pem} <- IdentityToolkitPublicKeys.get_for_kid(kid),
         {:ok, raw_claims} <- verify_with_cert(cookie, pem),
         :ok <- validate_claims(raw_claims, opts) do
      {:ok, Claims.new(raw_claims)}
    end
  end

  defp peek_header(cookie) do
    cookie
    |> JOSE.JWS.peek_protected()
    |> Jason.decode()
  rescue
    _ -> {:error, :invalid_cookie}
  end

  defp validate_header(%{"alg" => "RS256"}), do: :ok
  defp validate_header(%{"alg" => _}), do: {:error, :invalid_alg}
  defp validate_header(_), do: {:error, :invalid_header}

  defp fetch_kid(%{"kid" => kid}) when is_binary(kid) and kid != "", do: {:ok, kid}
  defp fetch_kid(_), do: {:error, :no_kid}

  defp verify_with_cert(cookie, pem) when is_binary(cookie) and is_binary(pem) do
    jwk = JOSE.JWK.from_pem(pem)

    case JOSE.JWT.verify_strict(jwk, ["RS256"], cookie) do
      {true, jwt, _jws} ->
        {_fields, claims} = JOSE.JWT.to_map(jwt)
        {:ok, claims}

      {false, _jwt, _jws} ->
        {:error, :invalid_signature}
    end
  rescue
    e in [ArgumentError, ErlangError] -> {:error, {:exception, e}}
  catch
    :exit, reason -> {:error, {:exit, reason}}
  end

  defp validate_claims(claims, opts) when is_map(claims) do
    now = System.system_time(:second)
    project_id = Config.firebase_project_id(opts)

    with {:ok, project_id} <- require_project_id(project_id),
         :ok <- require_aud(claims, project_id),
         :ok <- require_iss(claims, project_id),
         :ok <- require_sub(claims),
         :ok <- require_exp_future(claims, now),
         :ok <- require_iat_past(claims, now) do
      require_auth_time_past(claims, now)
    end
  end

  defp require_project_id(project_id) when is_binary(project_id) and project_id != "",
    do: {:ok, project_id}

  defp require_project_id(_), do: {:error, :missing_project_id}

  defp require_aud(%{"aud" => aud}, project_id) when aud == project_id, do: :ok
  defp require_aud(%{"aud" => _}, _project_id), do: {:error, :invalid_audience}
  defp require_aud(_, _project_id), do: {:error, :invalid_audience}

  defp require_iss(%{"iss" => iss}, project_id) do
    expected = "https://session.firebase.google.com/#{project_id}"
    if iss == expected, do: :ok, else: {:error, :invalid_issuer}
  end

  defp require_iss(_, _project_id), do: {:error, :invalid_issuer}

  defp require_sub(%{"sub" => sub}) when is_binary(sub) and sub != "", do: :ok
  defp require_sub(_), do: {:error, :invalid_sub}

  defp require_exp_future(%{"exp" => exp}, now) when is_number(exp) and exp > now, do: :ok
  defp require_exp_future(_claims, _now), do: {:error, :cookie_expired}

  defp require_iat_past(%{"iat" => iat}, now) when is_number(iat) and iat <= now, do: :ok
  defp require_iat_past(_claims, _now), do: {:error, :invalid_iat}

  defp require_auth_time_past(%{"auth_time" => at}, now) when is_number(at) and at <= now, do: :ok
  defp require_auth_time_past(_claims, _now), do: {:error, :invalid_auth_time}

  defp looks_like_jwt?(cookie) when is_binary(cookie) do
    length(String.split(cookie, ".", parts: 4)) == 3
  end
end
