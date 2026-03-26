defmodule SymphonyElixir.TelemetryTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Telemetry

  describe "metrics/0" do
    test "returns a list of telemetry metrics" do
      metrics = Telemetry.metrics()
      assert is_list(metrics)
      assert length(metrics) > 0

      metric_names = Enum.map(metrics, & &1.name)

      assert Enum.any?(metric_names, &match?([:symphony, :agent, :turn | _], &1))
      assert Enum.any?(metric_names, &match?([:symphony, :orchestrator | _], &1))
      assert Enum.any?(metric_names, &match?([:vm | _], &1))
    end
  end

  describe "emit helpers" do
    setup do
      test_pid = self()

      handler_id = "test-#{System.unique_integer([:positive])}"

      events = [
        [:symphony, :orchestrator, :dispatch],
        [:symphony, :orchestrator, :complete],
        [:symphony, :orchestrator, :retry],
        [:symphony, :agent, :turn, :start],
        [:symphony, :agent, :turn, :stop],
        [:symphony, :agent, :turn, :exception]
      ]

      :telemetry.attach_many(
        handler_id,
        events,
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      :ok
    end

    test "emit_dispatch sends orchestrator dispatch event" do
      Telemetry.emit_dispatch(%{issue_id: "test-1"})
      assert_receive {:telemetry_event, [:symphony, :orchestrator, :dispatch], %{count: 1}, %{issue_id: "test-1"}}
    end

    test "emit_complete sends orchestrator complete event" do
      Telemetry.emit_complete(%{issue_id: "test-2"})
      assert_receive {:telemetry_event, [:symphony, :orchestrator, :complete], %{count: 1}, %{issue_id: "test-2"}}
    end

    test "emit_retry sends orchestrator retry event" do
      Telemetry.emit_retry(%{issue_id: "test-3"})
      assert_receive {:telemetry_event, [:symphony, :orchestrator, :retry], %{count: 1}, %{issue_id: "test-3"}}
    end

    test "emit_turn_start sends agent turn start event" do
      Telemetry.emit_turn_start(%{agent_kind: "codex"})
      assert_receive {:telemetry_event, [:symphony, :agent, :turn, :start], %{count: 1}, %{agent_kind: "codex"}}
    end

    test "emit_turn_stop sends agent turn stop event with duration and tokens" do
      Telemetry.emit_turn_stop(1500, 4200, %{agent_kind: "claude_code"})

      assert_receive {:telemetry_event, [:symphony, :agent, :turn, :stop], %{duration: 1500, tokens: 4200},
                      %{agent_kind: "claude_code"}}
    end

    test "emit_turn_exception sends agent turn exception event" do
      Telemetry.emit_turn_exception(%{agent_kind: "codex", error: "timeout"})

      assert_receive {:telemetry_event, [:symphony, :agent, :turn, :exception], %{count: 1},
                      %{agent_kind: "codex", error: "timeout"}}
    end

    test "emit helpers work with empty metadata" do
      Telemetry.emit_dispatch()
      assert_receive {:telemetry_event, [:symphony, :orchestrator, :dispatch], %{count: 1}, %{}}
    end
  end
end
