defmodule Fireauth.Plug.HostedAuthFiles do
  @moduledoc """
  Serves Firebase authentication helper files with correct MIME types.

  Firebase ships helper files at `__/auth/*` (notably `handler` and `iframe`
  without file extensions). If you want redirect-mode auth on your own domain
  (custom `authDomain`), you must host these paths on the same origin.

  This plug serves the embedded copies from `:fireauth`'s `priv/static/__/auth/`.
  """

  import Plug.Conn

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{request_path: "/__/auth/" <> rest} = conn, _opts) do
    file_name = Path.basename(rest)
    file_path = Path.join([:code.priv_dir(:fireauth), "static", "__", "auth", rest])

    if File.exists?(file_path) do
      content_type = content_type_for(file_name)

      conn
      |> put_resp_content_type(content_type)
      |> send_file(200, file_path)
      |> halt()
    else
      conn
    end
  end

  def call(conn, _opts), do: conn

  defp content_type_for("handler"), do: "text/html"
  defp content_type_for("iframe"), do: "text/html"

  defp content_type_for(name) when is_binary(name) do
    case Path.extname(name) do
      ".js" -> "text/javascript"
      ".json" -> "application/json"
      ".html" -> "text/html"
      _ -> "application/octet-stream"
    end
  end
end
