defmodule Fireauth.Plug.FirebaseAuthProxy do
  @moduledoc """
  Transparent reverse proxy for Firebase hosted auth helper files.

  Proxies a fixed set of Firebase helper paths from your app domain to
  `https://<project>.firebaseapp.com` to make redirect-based auth work reliably
  across modern browsers (storage partitioning / third-party cookie restrictions).

  This plug uses `Fireauth.FirebaseUpstreamCache` (Agent) to cache successful responses
  and only hit the upstream on cache miss.
  """

  import Plug.Conn

  alias Fireauth.Config
  alias Fireauth.FirebaseUpstreamCache
  alias Fireauth.FirebaseUpstream

  @behaviour Plug

  @default_cache_ttl_ms 3_600_000

  @proxied_paths MapSet.new([
                   "/__/auth/handler",
                   "/__/auth/handler.js",
                   "/__/auth/experiments.js",
                   "/__/auth/iframe",
                   "/__/auth/iframe.js",
                   "/__/auth/links",
                   "/__/auth/links.js",
                   "/__/firebase/init.json"
                 ])

  @impl true
  def init(opts) when is_list(opts) do
    opts
    |> Keyword.put_new(:firebase_cache_ttl_ms, @default_cache_ttl_ms)
  end

  @impl true
  def call(%Plug.Conn{} = conn, opts) do
    if conn.method in ["GET", "HEAD"] and proxied_path?(conn.request_path) do
      key = cache_key(conn, opts)

      case Process.whereis(FirebaseUpstreamCache) do
        nil ->
          # If the cache agent isn't running (e.g. plug used without starting
          # the :fireauth app), still serve the proxied content without caching.
          fetch_and_serve(conn, opts, nil)

        _pid ->
          case FirebaseUpstreamCache.get(key) do
            {:hit, entry} ->
              serve_cached(conn, entry)

            :miss ->
              fetch_and_serve(conn, opts, key)
          end
      end
    else
      conn
    end
  end

  @doc false
  @spec proxied_path?(String.t()) :: boolean()
  def proxied_path?(path) when is_binary(path) do
    MapSet.member?(@proxied_paths, path)
  end

  defp cache_key(conn, opts) do
    project_id = Config.firebase_project_id(opts) || ""
    qs = if conn.query_string != "", do: conn.query_string, else: nil
    {project_id, conn.request_path, qs}
  end

  defp serve_cached(conn, %{status: status, headers: headers, body: body}) do
    conn
    |> put_cached_headers(headers)
    |> send_resp(status, body)
    |> halt()
  end

  defp put_cached_headers(conn, headers) when is_list(headers) do
    Enum.reduce(headers, conn, fn {k, v}, acc ->
      key = String.downcase(to_string(k))
      val = to_string(v)

      if key in ["content-length", "transfer-encoding", "connection"] do
        acc
      else
        put_resp_header(acc, key, val)
      end
    end)
  end

  defp fetch_and_serve(conn, opts, key_or_nil) do
    with {:ok, project_id} <- fetch_project_id(opts),
         {:ok, %{status: status, headers: headers, body: body}} <-
           FirebaseUpstream.fetch(project_id, conn.request_path, query_string(conn)) do
      content_type = content_type_from_headers(headers) || content_type_for_path(conn.request_path)

      resp_headers =
        headers
        |> normalize_headers()
        |> ensure_content_type(content_type)

      # Cache only successful responses; Firebase helper files are static-ish.
      if status == 200 and not is_nil(key_or_nil) do
        ttl_ms = Keyword.get(opts, :firebase_cache_ttl_ms, @default_cache_ttl_ms)

        FirebaseUpstreamCache.put(key_or_nil, %{
          status: status,
          headers: resp_headers,
          body: body,
          inserted_at_ms: System.system_time(:millisecond),
          ttl_ms: ttl_ms
        })
      end

      conn
      |> put_cached_headers(resp_headers)
      |> send_resp(status, body)
      |> halt()
    else
      {:error, :missing_project_id} ->
        conn

      {:error, _reason} ->
        conn
    end
  end

  defp query_string(%Plug.Conn{query_string: ""}), do: nil
  defp query_string(%Plug.Conn{query_string: qs}) when is_binary(qs), do: qs

  defp fetch_project_id(opts) do
    case Config.firebase_project_id(opts) do
      project_id when is_binary(project_id) and project_id != "" -> {:ok, project_id}
      _ -> {:error, :missing_project_id}
    end
  end

  defp normalize_headers(headers) when is_list(headers) do
    Enum.map(headers, fn {k, v} -> {to_string(k), to_string(v)} end)
  end

  defp ensure_content_type(headers, content_type) when is_list(headers) and is_binary(content_type) do
    if Enum.any?(headers, fn {k, _v} -> String.downcase(k) == "content-type" end) do
      headers
    else
      [{"content-type", content_type} | headers]
    end
  end

  defp content_type_from_headers(headers) when is_list(headers) do
    headers
    |> Enum.find_value(fn
      {k, v} when is_binary(k) ->
        if String.downcase(k) == "content-type", do: v, else: nil

      {k, v} ->
        if String.downcase(to_string(k)) == "content-type", do: to_string(v), else: nil
    end)
  end

  defp content_type_for_path(path) do
    case Path.basename(path) do
      "handler" -> "text/html"
      "iframe" -> "text/html"
      "links" -> "text/html"
      name ->
        case Path.extname(name) do
          ".js" -> "text/javascript"
          ".json" -> "application/json"
          ".html" -> "text/html"
          _ -> "application/octet-stream"
        end
    end
  end
end
