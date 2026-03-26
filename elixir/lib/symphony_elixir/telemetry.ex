defmodule SymphonyElixir.Telemetry do
  @moduledoc """
  Telemetry event definitions, metrics, and periodic measurements.

  ## Events

  Agent lifecycle:
  - `[:symphony, :agent, :turn, :start]` - Agent turn started
  - `[:symphony, :agent, :turn, :stop]` - Agent turn completed (measurements: duration, tokens)
  - `[:symphony, :agent, :turn, :exception]` - Agent turn failed

  Orchestrator:
  - `[:symphony, :orchestrator, :dispatch]` - Issue dispatched to agent
  - `[:symphony, :orchestrator, :complete]` - Issue completed
  - `[:symphony, :orchestrator, :retry]` - Issue scheduled for retry
  - `[:symphony, :orchestrator, :poll]` - Poll cycle executed

  Tracker:
  - `[:symphony, :tracker, :poll, :start]` - Tracker poll started
  - `[:symphony, :tracker, :poll, :stop]` - Tracker poll completed
  - `[:symphony, :tracker, :poll, :exception]` - Tracker poll failed
  """

  use Supervisor
  import Telemetry.Metrics

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Returns the list of telemetry metrics for this application.
  Can be consumed by reporters (Prometheus, StatsD, etc).
  """
  @spec metrics() :: [Telemetry.Metrics.t()]
  def metrics do
    [
      # Agent turn metrics
      counter("symphony.agent.turn.start.count",
        tags: [:agent_kind],
        description: "Number of agent turns started"
      ),
      summary("symphony.agent.turn.stop.duration",
        unit: {:native, :millisecond},
        tags: [:agent_kind],
        description: "Agent turn duration in milliseconds"
      ),
      sum("symphony.agent.turn.stop.tokens",
        tags: [:agent_kind],
        description: "Total tokens consumed by agent turns"
      ),
      counter("symphony.agent.turn.exception.count",
        tags: [:agent_kind],
        description: "Number of agent turn failures"
      ),

      # Orchestrator metrics
      counter("symphony.orchestrator.dispatch.count",
        description: "Issues dispatched to agents"
      ),
      counter("symphony.orchestrator.complete.count",
        description: "Issues completed"
      ),
      counter("symphony.orchestrator.retry.count",
        description: "Issues scheduled for retry"
      ),
      summary("symphony.orchestrator.poll.duration",
        unit: {:native, :millisecond},
        description: "Poll cycle duration"
      ),

      # Tracker metrics
      summary("symphony.tracker.poll.stop.duration",
        unit: {:native, :millisecond},
        description: "Tracker API poll duration"
      ),
      counter("symphony.tracker.poll.exception.count",
        description: "Tracker poll failures"
      ),

      # VM metrics
      last_value("vm.memory.total", unit: :byte),
      last_value("vm.memory.processes", unit: :byte),
      last_value("vm.total_run_queue_lengths.total"),
      last_value("vm.system_counts.process_count")
    ]
  end

  defp periodic_measurements do
    [
      {__MODULE__, :measure_orchestrator_state, []}
    ]
  end

  @doc false
  @spec measure_orchestrator_state() :: :ok
  def measure_orchestrator_state do
    case SymphonyElixir.Orchestrator.snapshot() do
      %{counts: counts, codex_totals: totals} ->
        running = Map.get(counts, :running, 0)
        retrying = Map.get(counts, :retrying, 0)

        :telemetry.execute(
          [:symphony, :orchestrator, :gauge],
          %{
            running_agents: running,
            retrying_agents: retrying,
            total_tokens: Map.get(totals || %{}, :total_tokens, 0),
            input_tokens: Map.get(totals || %{}, :input_tokens, 0),
            output_tokens: Map.get(totals || %{}, :output_tokens, 0)
          },
          %{}
        )

      _ ->
        :ok
    end
  end

  # -- Emit helpers for use in orchestrator/agent_runner --

  @spec emit_dispatch(map()) :: :ok
  def emit_dispatch(metadata \\ %{}) do
    :telemetry.execute([:symphony, :orchestrator, :dispatch], %{count: 1}, metadata)
  end

  @spec emit_complete(map()) :: :ok
  def emit_complete(metadata \\ %{}) do
    :telemetry.execute([:symphony, :orchestrator, :complete], %{count: 1}, metadata)
  end

  @spec emit_retry(map()) :: :ok
  def emit_retry(metadata \\ %{}) do
    :telemetry.execute([:symphony, :orchestrator, :retry], %{count: 1}, metadata)
  end

  @spec emit_turn_start(map()) :: :ok
  def emit_turn_start(metadata \\ %{}) do
    :telemetry.execute([:symphony, :agent, :turn, :start], %{count: 1}, metadata)
  end

  @spec emit_turn_stop(non_neg_integer(), non_neg_integer(), map()) :: :ok
  def emit_turn_stop(duration_ms, tokens, metadata \\ %{}) do
    :telemetry.execute(
      [:symphony, :agent, :turn, :stop],
      %{duration: duration_ms, tokens: tokens},
      metadata
    )
  end

  @spec emit_turn_exception(map()) :: :ok
  def emit_turn_exception(metadata \\ %{}) do
    :telemetry.execute([:symphony, :agent, :turn, :exception], %{count: 1}, metadata)
  end
end
