defmodule SymphonyElixir.JsonLogFormatter do
  @moduledoc """
  Structured JSON log formatter for production use.

  Outputs one JSON object per log line with fields:
  - `timestamp` - ISO 8601 timestamp
  - `level` - Log level (debug, info, warning, error)
  - `message` - Log message text
  - `metadata` - Any Logger metadata (issue_id, session_id, etc.)

  Enable by setting `SYMPHONY_LOG_FORMAT=json` or configuring in runtime.exs.
  """

  @spec format(atom(), term(), tuple(), keyword()) :: iodata()
  def format(level, message, timestamp, metadata) do
    log_entry = %{
      timestamp: format_timestamp(timestamp),
      level: level,
      message: IO.iodata_to_binary(message),
      metadata: format_metadata(metadata)
    }

    [Jason.encode_to_iodata!(log_entry), "\n"]
  rescue
    _ ->
      ts = format_timestamp(timestamp)
      ["#{ts} [#{level}] #{inspect(message)} #{inspect(metadata)}\n"]
  end

  defp format_timestamp({date, {h, m, s, ms}}) do
    {year, month, day} = date

    :io_lib.format("~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0B.~3..0BZ", [
      year, month, day, h, m, s, ms
    ])
    |> IO.iodata_to_binary()
  end

  defp format_metadata(metadata) do
    metadata
    |> Enum.reject(fn {k, _} -> k in [:erl_level, :gl, :time] end)
    |> Enum.map(fn {k, v} -> {k, safe_value(v)} end)
    |> Map.new()
  end

  defp safe_value(v) when is_binary(v), do: v
  defp safe_value(v) when is_atom(v), do: v
  defp safe_value(v) when is_number(v), do: v
  defp safe_value(v) when is_boolean(v), do: v
  defp safe_value(v) when is_pid(v), do: inspect(v)
  defp safe_value(v) when is_reference(v), do: inspect(v)
  defp safe_value(v) when is_list(v), do: inspect(v)
  defp safe_value(v) when is_map(v), do: inspect(v)
  defp safe_value(v), do: inspect(v)
end
