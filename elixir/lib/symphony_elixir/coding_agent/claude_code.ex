defmodule SymphonyElixir.CodingAgent.ClaudeCode do
  @moduledoc """
  CodingAgent implementation for Anthropic's Claude Code CLI.

  Launches Claude Code via `claude -p` with JSON streaming output,
  parses events, and normalizes them into the CodingAgent interface.
  """

  @behaviour SymphonyElixir.CodingAgent

  require Logger
  alias SymphonyElixir.Config

  @default_stall_timeout_ms 300_000

  @impl true
  @spec start_session(Path.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def start_session(workspace, opts) do
    worker_host = Keyword.get(opts, :worker_host)
    config = claude_code_config()
    command = config.command

    args = build_args(config, workspace)
    full_command = "#{command} #{Enum.join(args, " ")}"

    port_opts = [
      :binary,
      :exit_status,
      :use_stdio,
      :stderr_to_stdout,
      {:line, 1_048_576},
      {:cd, to_charlist(workspace)}
    ]

    port_opts =
      if worker_host do
        ssh_command = "ssh #{worker_host} 'cd #{workspace} && #{full_command}'"
        [{:args, ["-c", ssh_command]} | [{:name, ~c"/bin/sh"} | port_opts]]
      else
        [{:args, String.split(full_command)} | port_opts]
      end

    try do
      port = Port.open({:spawn_executable, System.find_executable("sh")}, [
        :binary,
        :exit_status,
        :use_stdio,
        :stderr_to_stdout,
        {:line, 1_048_576},
        {:cd, to_charlist(workspace)},
        {:args, ["-c", full_command]}
      ])

      session = %{
        port: port,
        workspace: workspace,
        worker_host: worker_host,
        session_id: generate_session_id(),
        config: config
      }

      Logger.info("Started Claude Code session session_id=#{session.session_id} workspace=#{workspace}")
      {:ok, session}
    rescue
      e ->
        Logger.error("Failed to start Claude Code: #{inspect(e)}")
        {:error, {:claude_code_start_failed, e}}
    end
  end

  @impl true
  @spec run_turn(map(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_turn(%{port: port, session_id: session_id} = _session, prompt, _issue, opts) do
    on_message = Keyword.get(opts, :on_message, fn _ -> :ok end)

    # Send the prompt via stdin
    Port.command(port, prompt <> "\n")

    # Collect output until turn completes
    result = collect_output(port, on_message, session_id)

    case result do
      {:ok, output} ->
        {:ok, %{
          result: :completed,
          session_id: session_id,
          thread_id: nil,
          turn_id: nil,
          output: output
        }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  @spec stop_session(map()) :: :ok
  def stop_session(%{port: port, session_id: session_id}) do
    Logger.info("Stopping Claude Code session session_id=#{session_id}")

    try do
      Port.close(port)
    rescue
      _ -> :ok
    end

    :ok
  end

  def stop_session(_), do: :ok

  @impl true
  @spec stall_timeout_ms() :: non_neg_integer()
  def stall_timeout_ms do
    config = claude_code_config()
    Map.get(config, :stall_timeout_ms, @default_stall_timeout_ms)
  end

  @impl true
  @spec tool_specs() :: [map()]
  def tool_specs, do: []

  # -- Private --

  defp claude_code_config do
    settings = Config.settings!()
    Map.get(settings, :claude_code, %{command: "claude", model: nil, stall_timeout_ms: @default_stall_timeout_ms})
  end

  defp build_args(config, _workspace) do
    args = ["-p", "--output-format", "stream-json"]

    args =
      case Map.get(config, :model) do
        nil -> args
        model -> args ++ ["--model", model]
      end

    args
  end

  defp collect_output(port, on_message, session_id) do
    timeout = claude_code_config() |> Map.get(:turn_timeout_ms, 3_600_000)
    collect_output_loop(port, on_message, session_id, [], timeout)
  end

  defp collect_output_loop(port, on_message, session_id, acc, timeout) do
    receive do
      {^port, {:data, {:eol, line}}} ->
        case parse_stream_line(line) do
          {:event, event} ->
            update = normalize_event(event, session_id)
            on_message.(update)
            collect_output_loop(port, on_message, session_id, [line | acc], timeout)

          :continue ->
            collect_output_loop(port, on_message, session_id, [line | acc], timeout)
        end

      {^port, {:exit_status, 0}} ->
        {:ok, acc |> Enum.reverse() |> Enum.join("\n")}

      {^port, {:exit_status, code}} ->
        {:error, {:claude_code_exit, code}}
    after
      timeout ->
        {:error, :turn_timeout}
    end
  end

  defp parse_stream_line(line) do
    case Jason.decode(line) do
      {:ok, event} -> {:event, event}
      _ -> :continue
    end
  end

  defp normalize_event(event, session_id) do
    %{
      event: event_type(event),
      timestamp: DateTime.utc_now(),
      agent_pid: nil,
      input_tokens: get_in(event, ["usage", "input_tokens"]) || 0,
      output_tokens: get_in(event, ["usage", "output_tokens"]) || 0,
      total_tokens: (get_in(event, ["usage", "input_tokens"]) || 0) + (get_in(event, ["usage", "output_tokens"]) || 0),
      session_id: session_id,
      rate_limits: nil,
      payload: event,
      raw: Jason.encode!(event)
    }
  end

  defp event_type(%{"type" => type}), do: String.to_atom(type)
  defp event_type(_), do: :unknown

  defp generate_session_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
