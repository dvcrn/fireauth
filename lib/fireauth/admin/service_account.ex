defmodule Fireauth.Admin.ServiceAccount do
  @moduledoc false

  @type t :: %{
          optional(String.t()) => term()
        }

  @spec decode(nil | binary() | map()) :: {:ok, t()} | {:error, term()}
  def decode(nil), do: {:error, :missing_service_account}

  def decode(%{} = sa), do: {:ok, normalize_keys(sa)}

  def decode(sa) when is_binary(sa) do
    sa = String.trim(sa)

    cond do
      sa == "" ->
        {:error, :missing_service_account}

      String.starts_with?(sa, "{") ->
        decode_json(sa)

      true ->
        # Commonly stored as base64 in env vars to avoid newline escaping issues.
        with {:ok, decoded} <- Base.decode64(sa),
             decoded when is_binary(decoded) <- String.trim(decoded),
             true <- String.starts_with?(decoded, "{") do
          decode_json(decoded)
        else
          _ -> {:error, :invalid_service_account_format}
        end
    end
  end

  def decode(_), do: {:error, :invalid_service_account_format}

  @spec fetch_required(t(), String.t()) :: {:ok, binary()} | {:error, term()}
  def fetch_required(%{} = sa, key) when is_binary(key) do
    case Map.get(sa, key) do
      v when is_binary(v) and v != "" -> {:ok, v}
      _ -> {:error, {:missing_key, key}}
    end
  end

  defp decode_json(json) do
    case Jason.decode(json) do
      {:ok, %{} = sa} -> {:ok, normalize_keys(sa)}
      {:ok, _} -> {:error, :invalid_service_account_json}
      {:error, reason} -> {:error, {:invalid_service_account_json, reason}}
    end
  end

  defp normalize_keys(%{} = sa) do
    Map.new(sa, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {to_string(k), v}
    end)
  end
end
