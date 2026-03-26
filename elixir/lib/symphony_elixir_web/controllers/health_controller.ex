defmodule SymphonyElixirWeb.HealthController do
  @moduledoc """
  Health and readiness check endpoints.

  These bypass authentication so load balancers and orchestrators can probe them.
  """

  use Phoenix.Controller, formats: [:json]

  @spec health(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def health(conn, _params) do
    status = %{
      status: "ok",
      version: Application.spec(:symphony_elixir, :vsn) |> to_string(),
      uptime_seconds: uptime_seconds()
    }

    json(conn, status)
  end

  @spec ready(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def ready(conn, _params) do
    checks = %{
      database: check_database(),
      orchestrator: check_orchestrator()
    }

    all_ok = Enum.all?(Map.values(checks), &(&1 == "ok"))

    conn
    |> put_status(if(all_ok, do: 200, else: 503))
    |> json(%{status: if(all_ok, do: "ready", else: "not_ready"), checks: checks})
  end

  defp check_database do
    case Ecto.Adapters.SQL.query(SymphonyElixir.Repo, "SELECT 1", []) do
      {:ok, _} -> "ok"
      _ -> "unavailable"
    end
  rescue
    _ -> "unavailable"
  end

  defp check_orchestrator do
    if Process.whereis(SymphonyElixir.Orchestrator), do: "ok", else: "unavailable"
  end

  defp uptime_seconds do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    div(uptime_ms, 1000)
  end
end
