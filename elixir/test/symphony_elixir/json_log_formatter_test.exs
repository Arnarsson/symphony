defmodule SymphonyElixir.JsonLogFormatterTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.JsonLogFormatter

  @timestamp {{2026, 3, 26}, {14, 30, 45, 123}}

  describe "format/4" do
    test "produces valid JSON with expected fields" do
      result =
        JsonLogFormatter.format(:info, "hello world", @timestamp, [])
        |> IO.iodata_to_binary()

      assert String.ends_with?(result, "\n")
      decoded = Jason.decode!(String.trim(result))

      assert decoded["level"] == "info"
      assert decoded["message"] == "hello world"
      assert decoded["timestamp"] == "2026-03-26T14:30:45.123Z"
      assert is_map(decoded["metadata"])
    end

    test "includes metadata key-value pairs" do
      metadata = [issue_id: "issue-1", session_id: "sess-abc"]

      result =
        JsonLogFormatter.format(:debug, "with meta", @timestamp, metadata)
        |> IO.iodata_to_binary()

      decoded = Jason.decode!(String.trim(result))
      assert decoded["metadata"]["issue_id"] == "issue-1"
      assert decoded["metadata"]["session_id"] == "sess-abc"
    end

    test "filters out internal metadata keys" do
      metadata = [erl_level: :info, gl: self(), time: 12345, custom: "kept"]

      result =
        JsonLogFormatter.format(:warning, "filtered", @timestamp, metadata)
        |> IO.iodata_to_binary()

      decoded = Jason.decode!(String.trim(result))
      refute Map.has_key?(decoded["metadata"], "erl_level")
      refute Map.has_key?(decoded["metadata"], "gl")
      refute Map.has_key?(decoded["metadata"], "time")
      assert decoded["metadata"]["custom"] == "kept"
    end

    test "handles iodata messages" do
      result =
        JsonLogFormatter.format(:error, ["multi", "part"], @timestamp, [])
        |> IO.iodata_to_binary()

      decoded = Jason.decode!(String.trim(result))
      assert decoded["message"] == "multipart"
    end

    test "serializes pid metadata as string" do
      metadata = [pid: self()]

      result =
        JsonLogFormatter.format(:info, "pid test", @timestamp, metadata)
        |> IO.iodata_to_binary()

      decoded = Jason.decode!(String.trim(result))
      assert is_binary(decoded["metadata"]["pid"])
      assert decoded["metadata"]["pid"] =~ "#PID<"
    end

    test "handles all log levels" do
      for level <- [:debug, :info, :warning, :error] do
        result =
          JsonLogFormatter.format(level, "test", @timestamp, [])
          |> IO.iodata_to_binary()

        decoded = Jason.decode!(String.trim(result))
        assert decoded["level"] == Atom.to_string(level)
      end
    end
  end
end
