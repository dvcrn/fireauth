defmodule Fireauth.Firebase do
  @moduledoc """
  Firebase claim helpers.

  Token verification is handled by `Fireauth.TokenValidator` (default:
  `Fireauth.FirebaseTokenValidator`).
  """

  alias Fireauth.TokenValidator

  @type id_token :: String.t()

  @typedoc """
  Map of identity provider => list of provider-specific user IDs.
  Example: %{"email" => ["git@d.sh"], "github.com" => ["688326"]}
  """
  @type provider_identity_map :: %{optional(String.t()) => [String.t()]}

  @typedoc """
  Verified Firebase ID token claims. String keys as provided by the JWT.
  """
  @type firebase_claims :: %{optional(String.t()) => term()}

  @typedoc """
  Attributes derived from Firebase claims.
  """
  @type user_attrs :: %{
          required(:firebase_uid) => String.t(),
          optional(:email) => String.t() | nil,
          optional(:name) => String.t() | nil,
          optional(:avatar_url) => String.t() | nil,
          optional(:email_verified) => boolean() | nil,
          optional(:sign_in_provider) => String.t() | nil,
          optional(:provider_uid) => String.t() | nil,
          optional(:github_uid) => String.t() | nil,
          optional(:google_uid) => String.t() | nil,
          optional(:identities) => provider_identity_map | nil
        }

  @doc """
  Verify a Firebase ID token and return its claims.

  Delegates to `Fireauth.TokenValidator` (adapter pattern).
  """
  @spec verify_id_token(id_token(), keyword()) :: {:ok, firebase_claims()} | {:error, term()}
  def verify_id_token(token, opts \\ []) when is_binary(token) and is_list(opts) do
    TokenValidator.verify_id_token(token, opts)
  end

  @doc """
  Derive basic user attrs from verified claims.
  """
  @spec claims_to_user_attrs(firebase_claims()) :: user_attrs()
  def claims_to_user_attrs(%{} = claims) do
    firebase = Map.get(claims, "firebase") || %{}
    identities = Map.get(firebase, "identities") || %{}
    sign_in_provider = Map.get(firebase, "sign_in_provider")

    github_uid = extract_provider_uid(identities, "github.com")
    google_uid = extract_provider_uid(identities, "google.com")

    provider_uid =
      case sign_in_provider do
        "github.com" -> github_uid
        "google.com" -> google_uid
        _ -> nil
      end

    %{
      firebase_uid: to_string(claims["user_id"] || claims["sub"] || ""),
      email: claims["email"],
      name: claims["name"] || claims["email"],
      avatar_url: claims["picture"],
      email_verified: claims["email_verified"],
      sign_in_provider: sign_in_provider,
      provider_uid: provider_uid,
      github_uid: github_uid,
      google_uid: google_uid,
      identities: if(map_size(identities) == 0, do: nil, else: identities)
    }
  end

  defp extract_provider_uid(identities, provider) when is_map(identities) and is_binary(provider) do
    case Map.get(identities, provider) do
      [uid | _] when is_binary(uid) -> uid
      _ -> nil
    end
  end

  defp extract_provider_uid(_, _), do: nil

  # No token verification internals here. See `Fireauth.FirebaseTokenValidator`.
end
