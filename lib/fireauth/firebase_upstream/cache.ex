defmodule Fireauth.FirebaseUpstream.Cache do
  @moduledoc """
  In-memory cache for Firebase hosted auth helper files.

  Used by `Fireauth.Plug.FirebaseAuthProxy` so `/__/auth/*` is only fetched
  from upstream (`https://<project>.firebaseapp.com`) on cache miss.
  """

  use Agent

  require Logger

  @type key :: {String.t(), String.t(), String.t() | nil}

  @type entry :: %{
          status: pos_integer(),
          headers: [{String.t(), String.t()}],
          body: binary(),
          inserted_at_ms: non_neg_integer(),
          ttl_ms: non_neg_integer()
        }

  def start_link(_opts \\ []) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @spec get(key()) :: {:hit, entry()} | :miss
  def get(key) do
    now = now_ms()

    Agent.get(__MODULE__, fn cache ->
      case Map.get(cache, key) do
        %{} = entry ->
          if expired?(entry, now) do
            :miss
          else
            Logger.debug("fireauth: cache hit for #{inspect(key)}")
            {:hit, entry}
          end

        _ ->
          :miss
      end
    end)
  end

  @spec put(key(), entry()) :: :ok
  def put(key, %{} = entry) do
    Agent.update(__MODULE__, &Map.put(&1, key, entry))
  end

  @spec delete(key()) :: :ok
  def delete(key) do
    Agent.update(__MODULE__, &Map.delete(&1, key))
  end

  @spec clear() :: :ok
  def clear do
    Agent.update(__MODULE__, fn _ -> %{} end)
  end

  defp expired?(%{inserted_at_ms: ts, ttl_ms: ttl}, now)
       when is_integer(ts) and is_integer(ttl) and ttl > 0 do
    now - ts > ttl
  end

  defp expired?(_entry, _now), do: false

  defp now_ms, do: System.system_time(:millisecond)
end
