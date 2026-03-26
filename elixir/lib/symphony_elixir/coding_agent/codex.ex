defmodule SymphonyElixir.CodingAgent.Codex do
  @moduledoc """
  CodingAgent implementation wrapping the existing Codex AppServer.

  Delegates to `SymphonyElixir.Codex.AppServer` and translates its
  protocol into the normalized CodingAgent interface.
  """

  @behaviour SymphonyElixir.CodingAgent

  alias SymphonyElixir.{Codex.AppServer, Codex.DynamicTool, Config}

  @impl true
  @spec start_session(Path.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def start_session(workspace, opts) do
    AppServer.start_session(workspace, opts)
  end

  @impl true
  @spec run_turn(map(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_turn(session, prompt, issue, opts) do
    AppServer.run_turn(session, prompt, issue, opts)
  end

  @impl true
  @spec stop_session(map()) :: :ok
  def stop_session(session) do
    AppServer.stop_session(session)
  end

  @impl true
  @spec stall_timeout_ms() :: non_neg_integer()
  def stall_timeout_ms do
    Config.settings!().codex.stall_timeout_ms
  end

  @impl true
  @spec tool_specs() :: [map()]
  def tool_specs do
    DynamicTool.tool_specs()
  end
end
