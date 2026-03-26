defmodule SymphonyElixirWeb.MetricsController do
  @moduledoc """
  Exposes telemetry metrics in a simple text format for monitoring.
  """

  use Phoenix.Controller, formats: [:json]

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params) do
    metrics = collect_metrics()

    conn
    |> put_resp_content_type("application/json")
    |> json(metrics)
  end

  defp collect_metrics do
    case SymphonyElixir.Orchestrator.snapshot() do
      %{running: running_list, retrying: retrying_list, agent_totals: totals, rate_limits: rate_limits} ->
        %{
          orchestrator: %{
            running_agents: length(running_list),
            retrying_agents: length(retrying_list)
          },
          tokens: %{
            input: Map.get(totals || %{}, :input_tokens, 0),
            output: Map.get(totals || %{}, :output_tokens, 0),
            total: Map.get(totals || %{}, :total_tokens, 0),
            seconds_running: Map.get(totals || %{}, :seconds_running, 0)
          },
          rate_limits: rate_limits,
          vm: vm_metrics()
        }

      _ ->
        %{status: "unavailable", vm: vm_metrics()}
    end
  end

  defp vm_metrics do
    memory = :erlang.memory()

    %{
      memory_total_mb: div(memory[:total], 1_048_576),
      memory_processes_mb: div(memory[:processes], 1_048_576),
      process_count: :erlang.system_info(:process_count),
      uptime_seconds: div(elem(:erlang.statistics(:wall_clock), 0), 1000)
    }
  end
end
