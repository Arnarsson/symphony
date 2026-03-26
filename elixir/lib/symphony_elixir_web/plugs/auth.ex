defmodule SymphonyElixirWeb.Plugs.Auth do
  @moduledoc """
  Authentication plug for Symphony's API and dashboard.

  Supports bearer token authentication via the `SYMPHONY_AUTH_TOKEN` environment
  variable. When the token is not configured, all requests are allowed (development mode).

  For API requests: checks the `Authorization: Bearer <token>` header.
  For browser requests: checks a `_symphony_token` session key or query param `token`.
  """

  import Plug.Conn
  @behaviour Plug

  @impl true
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @skip_auth_paths ["/health", "/ready", "/metrics"]

  @impl true
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    if conn.request_path in @skip_auth_paths do
      conn
    else
      case auth_token() do
        nil -> conn
        expected_token -> authenticate(conn, expected_token)
      end
    end
  end

  defp authenticate(conn, expected_token) do
    cond do
      valid_bearer_token?(conn, expected_token) ->
        conn

      valid_session_token?(conn, expected_token) ->
        conn

      valid_query_token?(conn, expected_token) ->
        conn
        |> fetch_session()
        |> put_session("_symphony_token", expected_token)

      true ->
        conn
        |> put_resp_content_type(content_type(conn))
        |> send_resp(401, unauthorized_body(conn))
        |> halt()
    end
  end

  defp valid_bearer_token?(conn, expected) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> Plug.Crypto.secure_compare(token, expected)
      _ -> false
    end
  end

  defp valid_session_token?(conn, expected) do
    conn = fetch_session(conn)

    case get_session(conn, "_symphony_token") do
      nil -> false
      token -> Plug.Crypto.secure_compare(token, expected)
    end
  end

  defp valid_query_token?(conn, expected) do
    conn = fetch_query_params(conn)

    case conn.query_params["token"] do
      nil -> false
      token -> Plug.Crypto.secure_compare(token, expected)
    end
  end

  defp content_type(conn) do
    if api_request?(conn), do: "application/json", else: "text/plain"
  end

  defp unauthorized_body(conn) do
    if api_request?(conn) do
      Jason.encode!(%{error: %{code: "unauthorized", message: "Invalid or missing authentication token"}})
    else
      "Unauthorized. Provide token via ?token=<token> query parameter or Authorization header."
    end
  end

  defp api_request?(conn) do
    String.starts_with?(conn.request_path, "/api/")
  end

  defp auth_token do
    System.get_env("SYMPHONY_AUTH_TOKEN")
  end
end
