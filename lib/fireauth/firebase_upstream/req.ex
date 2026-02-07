defmodule Fireauth.FirebaseUpstream.Req do
  @moduledoc false

  @behaviour Fireauth.FirebaseUpstream

  @impl true
  def fetch(project_id, path, query_string)
      when is_binary(project_id) and is_binary(path) do
    url = build_url(project_id, path, query_string)

    case Req.get(url, decode_body: false, redirect: true) do
      {:ok, %{status: status, headers: headers, body: body}} ->
        {:ok,
         %{
           status: status,
           headers: headers_to_kv_list(headers),
           body: to_binary(body)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_url(project_id, path, query_string) do
    domain = Application.get_env(:fireauth, :firebaseapp_domain, "firebaseapp.com")
    base = "https://#{project_id}.#{domain}#{path}"

    case query_string do
      qs when is_binary(qs) and qs != "" -> base <> "?" <> qs
      _ -> base
    end
  end

  defp headers_to_kv_list(%{} = headers) do
    Enum.map(headers, fn {k, v} -> {to_string(k), normalize_header_value(v)} end)
  end

  defp headers_to_kv_list(headers) when is_list(headers) do
    Enum.map(headers, fn {k, v} -> {to_string(k), normalize_header_value(v)} end)
  end

  defp normalize_header_value(v) when is_binary(v), do: v

  defp normalize_header_value(v) when is_list(v) do
    cond do
      v == [] ->
        ""

      Enum.all?(v, &is_binary/1) ->
        Enum.join(v, ", ")

      true ->
        to_string(v)
    end
  end

  defp normalize_header_value(v), do: to_string(v)

  defp to_binary(data) when is_binary(data), do: data
  defp to_binary(data) when is_list(data), do: IO.iodata_to_binary(data)
end
