defmodule SymphonyElixir.CodingAgent do
  @moduledoc """
  Behaviour for coding agents that execute work on issues.

  Each implementation wraps a specific agent CLI (Codex, Claude Code, etc.)
  and translates its protocol into Symphony's normalized session/turn model.
  """

  alias SymphonyElixir.Config

  @type session :: map()

  @type turn_result :: %{
          result: atom(),
          session_id: String.t() | nil,
          thread_id: String.t() | nil,
          turn_id: String.t() | nil
        }

  @type agent_update :: %{
          event: atom(),
          timestamp: DateTime.t(),
          agent_pid: String.t() | nil,
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer(),
          total_tokens: non_neg_integer(),
          session_id: String.t() | nil,
          rate_limits: map() | nil,
          payload: term(),
          raw: String.t() | nil
        }

  @doc """
  Starts a persistent agent session in the given workspace.
  Returns an opaque session handle used by `run_turn/4` and `stop_session/1`.
  """
  @callback start_session(workspace :: Path.t(), opts :: keyword()) ::
              {:ok, session()} | {:error, term()}

  @doc """
  Runs a single turn (prompt submission + completion) within an existing session.
  """
  @callback run_turn(session(), prompt :: String.t(), issue :: map(), opts :: keyword()) ::
              {:ok, turn_result()} | {:error, term()}

  @doc """
  Tears down the agent session and releases resources.
  """
  @callback stop_session(session()) :: :ok

  @doc """
  Returns the stall timeout for this agent type in milliseconds.
  """
  @callback stall_timeout_ms() :: non_neg_integer()

  @doc """
  Returns tool specs this agent should register, in the agent's native format.
  """
  @callback tool_specs() :: [map()]

  @doc """
  Returns the module implementing the CodingAgent behaviour based on config.
  """
  @spec agent_module() :: module()
  def agent_module do
    case Config.settings!() do
      %{agent: %{kind: "claude_code"}} -> SymphonyElixir.CodingAgent.ClaudeCode
      _ -> SymphonyElixir.CodingAgent.Codex
    end
  end
end
