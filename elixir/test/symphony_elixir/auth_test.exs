defmodule SymphonyElixirWeb.Plugs.AuthTest do
  use ExUnit.Case, async: true
  use Plug.Test

  alias SymphonyElixirWeb.Plugs.Auth

  @opts Auth.init([])

  describe "when SYMPHONY_AUTH_TOKEN is not set" do
    setup do
      prev = System.get_env("SYMPHONY_AUTH_TOKEN")
      System.delete_env("SYMPHONY_AUTH_TOKEN")
      on_exit(fn ->
        if prev, do: System.put_env("SYMPHONY_AUTH_TOKEN", prev)
      end)
      :ok
    end

    test "allows all requests through" do
      conn =
        conn(:get, "/api/v1/state")
        |> init_test_session(%{})
        |> Auth.call(@opts)

      refute conn.halted
    end
  end

  describe "when SYMPHONY_AUTH_TOKEN is set" do
    @token "test-secret-token-12345"

    setup do
      prev = System.get_env("SYMPHONY_AUTH_TOKEN")
      System.put_env("SYMPHONY_AUTH_TOKEN", @token)
      on_exit(fn ->
        if prev do
          System.put_env("SYMPHONY_AUTH_TOKEN", prev)
        else
          System.delete_env("SYMPHONY_AUTH_TOKEN")
        end
      end)
      :ok
    end

    test "blocks requests without auth" do
      conn =
        conn(:get, "/api/v1/state")
        |> init_test_session(%{})
        |> Auth.call(@opts)

      assert conn.halted
      assert conn.status == 401
    end

    test "allows requests with valid bearer token" do
      conn =
        conn(:get, "/api/v1/state")
        |> put_req_header("authorization", "Bearer #{@token}")
        |> init_test_session(%{})
        |> Auth.call(@opts)

      refute conn.halted
    end

    test "blocks requests with invalid bearer token" do
      conn =
        conn(:get, "/api/v1/state")
        |> put_req_header("authorization", "Bearer wrong-token")
        |> init_test_session(%{})
        |> Auth.call(@opts)

      assert conn.halted
      assert conn.status == 401
    end

    test "allows requests with valid query param token" do
      conn =
        conn(:get, "/api/v1/state?token=#{@token}")
        |> init_test_session(%{})
        |> Auth.call(@opts)

      refute conn.halted
    end

    test "skips auth for /health endpoint" do
      conn =
        conn(:get, "/health")
        |> init_test_session(%{})
        |> Auth.call(@opts)

      refute conn.halted
    end

    test "skips auth for /ready endpoint" do
      conn =
        conn(:get, "/ready")
        |> init_test_session(%{})
        |> Auth.call(@opts)

      refute conn.halted
    end

    test "returns JSON error for API requests" do
      conn =
        conn(:get, "/api/v1/state")
        |> init_test_session(%{})
        |> Auth.call(@opts)

      assert conn.halted
      body = Jason.decode!(conn.resp_body)
      assert body["error"]["code"] == "unauthorized"
    end
  end
end
