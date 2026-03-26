defmodule SymphonyElixir.CodingAgentTest do
  use SymphonyElixir.TestSupport

  describe "agent_module/0" do
    test "defaults to Codex adapter" do
      assert CodingAgent.agent_module() == SymphonyElixir.CodingAgent.Codex
    end

    test "returns ClaudeCode when agent.kind is claude_code" do
      write_workflow_file!(workflow_file(), """
      ---
      tracker:
        kind: linear
        project_slug: TEST
        api_key: test-key
      agent:
        kind: claude_code
      ---
      Test prompt
      """)

      WorkflowStore.force_reload()
      assert CodingAgent.agent_module() == SymphonyElixir.CodingAgent.ClaudeCode
    end
  end

  describe "CodingAgent.Codex" do
    test "implements stall_timeout_ms/0" do
      assert is_integer(SymphonyElixir.CodingAgent.Codex.stall_timeout_ms())
      assert SymphonyElixir.CodingAgent.Codex.stall_timeout_ms() > 0
    end

    test "implements tool_specs/0" do
      assert is_list(SymphonyElixir.CodingAgent.Codex.tool_specs())
    end
  end

  defp workflow_file do
    Workflow.get_workflow_file_path()
  end
end
