defmodule Fireauth.FirebaseUpstream.SecureTokenPublicKeys do
  @moduledoc """
  Caches the Google SecureToken public keys used to verify Firebase ID tokens.

  This is started under `Fireauth.Application` and will fetch keys on boot.
  TTL is derived from the `Cache-Control: max-age` header returned by Google.
  """

  use Agent

  require Logger

  @x509_url "https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com"
  @fallback_ttl_seconds 3600

  @type state :: %{
          keys: %{optional(String.t()) => String.t()},
          expires_at_s: non_neg_integer()
        }

  def start_link(opts \\ []) do
    Agent.start_link(fn -> init_state(opts) end, name: __MODULE__)
  end

  @doc false
  @spec put_keys(map(), non_neg_integer()) :: :ok
  def put_keys(%{} = keys, ttl_seconds) when is_integer(ttl_seconds) and ttl_seconds >= 0 do
    ensure_started!()
    now_s = now_s()

    Agent.update(__MODULE__, fn _st ->
      %{keys: keys, expires_at_s: now_s + ttl_seconds}
    end)
  end

  @spec get_for_kid(String.t()) :: {:ok, String.t()} | {:error, term()}
  def get_for_kid(kid) when is_binary(kid) and kid != "" do
    with {:ok, keys} <- get_keys() do
      case Map.get(keys, kid) do
        pem when is_binary(pem) and pem != "" ->
          {:ok, pem}

        _ ->
          # Key rotations can happen; force refresh once on miss.
          with {:ok, keys2} <- refresh_keys() do
            case Map.get(keys2, kid) do
              pem when is_binary(pem) and pem != "" -> {:ok, pem}
              _ -> {:error, :cert_not_found}
            end
          end
      end
    end
  end

  def get_for_kid(_), do: {:error, :cert_not_found}

  @spec get_keys() :: {:ok, map()} | {:error, term()}
  def get_keys do
    ensure_started!()

    now_s = now_s()

    {keys, _expires_at_s} =
      Agent.get_and_update(__MODULE__, fn %{keys: keys, expires_at_s: exp} = st ->
        if exp > now_s and map_size(keys) > 0 do
          {{keys, exp}, st}
        else
          case fetch_keys() do
            {:ok, keys2, ttl_s} ->
              exp2 = now_s + ttl_s
              {{keys2, exp2}, %{st | keys: keys2, expires_at_s: exp2}}

            {:error, _reason} ->
              # If refresh fails, keep whatever we had; shorten expiry so we retry soon.
              retry_exp = now_s + 60
              {{keys, retry_exp}, %{st | expires_at_s: retry_exp}}
          end
        end
      end)

    if map_size(keys) > 0 do
      {:ok, keys}
    else
      {:error, :no_keys}
    end
  end

  @spec refresh_keys() :: {:ok, map()} | {:error, term()}
  def refresh_keys do
    ensure_started!()
    now_s = now_s()
    Logger.debug("fireauth: refreshing Firebase SecureToken public keys")

    Agent.get_and_update(__MODULE__, fn %{keys: _keys} = st ->
      case fetch_keys() do
        {:ok, keys2, ttl_s} ->
          exp2 = now_s + ttl_s
          {{:ok, keys2}, %{st | keys: keys2, expires_at_s: exp2}}

        {:error, reason} ->
          # Keep old keys.
          {{:error, reason}, st}
      end
    end)
    |> case do
      {:ok, keys} -> {:ok, keys}
      {:error, reason} -> {:error, reason}
    end
  end

  defp init_state(_opts) do
    Logger.debug("fireauth: prefetching Firebase SecureToken public keys")

    case fetch_keys() do
      {:ok, keys, ttl_s} ->
        Logger.info(
          "fireauth: downloaded Firebase SecureToken public keys count=#{map_size(keys)} ttl_seconds=#{ttl_s}"
        )

        now_s = now_s()
        %{keys: keys, expires_at_s: now_s + ttl_s}

      {:error, reason} ->
        Logger.warning(
          "fireauth: failed to download Firebase SecureToken public keys reason=#{inspect(reason)}"
        )

        %{keys: %{}, expires_at_s: 0}
    end
  end

  defp fetch_keys do
    Logger.debug("fireauth: downloading public keys from #{@x509_url}")

    case Req.get(@x509_url, decode_body: false, redirect: true) do
      {:ok, %{status: 200, headers: headers, body: body}} ->
        with {:ok, keys} <- Jason.decode(to_binary(body)) do
          ttl_s = cache_max_age_seconds(headers) || @fallback_ttl_seconds
          {:ok, keys, ttl_s}
        end

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, to_binary(body)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp cache_max_age_seconds(headers) when is_list(headers) do
    headers
    |> Enum.find_value(fn {k, v} ->
      key = k |> to_string() |> String.downcase()
      if key == "cache-control", do: parse_max_age(v), else: nil
    end)
  end

  defp cache_max_age_seconds(%{} = headers) do
    headers
    |> Enum.find_value(fn {k, v} ->
      key = k |> to_string() |> String.downcase()
      if key == "cache-control", do: parse_max_age(v), else: nil
    end)
  end

  defp parse_max_age(v) do
    v =
      cond do
        is_binary(v) -> v
        is_list(v) and Enum.all?(v, &is_binary/1) -> Enum.join(v, ", ")
        true -> to_string(v)
      end

    case Regex.run(~r/max-age=(\d+)/, v) do
      [_, digits] ->
        case Integer.parse(digits) do
          {n, _} when n > 0 -> n
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp ensure_started! do
    case Process.whereis(__MODULE__) do
      nil ->
        raise "Fireauth.FirebaseUpstream.SecureTokenPublicKeys is not started (start the :fireauth application)"

      _pid ->
        :ok
    end
  end

  defp now_s, do: System.system_time(:second)

  defp to_binary(data) when is_binary(data), do: data
  defp to_binary(data) when is_list(data), do: IO.iodata_to_binary(data)
end
