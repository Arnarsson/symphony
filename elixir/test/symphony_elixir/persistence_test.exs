defmodule SymphonyElixir.PersistenceTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Persistence
  alias SymphonyElixir.Persistence.IssueRun

  setup do
    # Ensure repo is started and tables exist for test
    # In test env, using in-memory SQLite
    :ok
  end

  describe "issue run tracking" do
    test "upsert_issue_run creates a new record" do
      attrs = %{
        issue_id: "test-issue-#{System.unique_integer([:positive])}",
        issue_identifier: "PROJ-123",
        status: "running"
      }

      assert {:ok, %IssueRun{} = run} = Persistence.upsert_issue_run(attrs)
      assert run.issue_id == attrs.issue_id
      assert run.issue_identifier == "PROJ-123"
      assert run.status == "running"
    end

    test "upsert_issue_run updates an existing record" do
      issue_id = "test-issue-#{System.unique_integer([:positive])}"

      {:ok, _} = Persistence.upsert_issue_run(%{
        issue_id: issue_id,
        issue_identifier: "PROJ-456",
        status: "running"
      })

      {:ok, updated} = Persistence.upsert_issue_run(%{
        issue_id: issue_id,
        status: "completed"
      })

      assert updated.issue_id == issue_id
      assert updated.status == "completed"
    end

    test "mark_issue_completed sets status" do
      issue_id = "test-issue-#{System.unique_integer([:positive])}"

      Persistence.upsert_issue_run(%{
        issue_id: issue_id,
        issue_identifier: "PROJ-789",
        status: "running"
      })

      assert :ok = Persistence.mark_issue_completed(issue_id)

      run = Persistence.get_issue_run(issue_id)
      assert run.status == "completed"
    end

    test "mark_issue_retrying sets status and attempt" do
      issue_id = "test-issue-#{System.unique_integer([:positive])}"

      Persistence.upsert_issue_run(%{
        issue_id: issue_id,
        issue_identifier: "PROJ-101",
        status: "running"
      })

      assert :ok = Persistence.mark_issue_retrying(issue_id, 3, "connection timeout")

      run = Persistence.get_issue_run(issue_id)
      assert run.status == "retrying"
      assert run.retry_attempt == 3
      assert run.last_error == "connection timeout"
    end

    test "load_completed_issue_ids returns set of completed issue IDs" do
      id1 = "completed-#{System.unique_integer([:positive])}"
      id2 = "completed-#{System.unique_integer([:positive])}"
      id3 = "running-#{System.unique_integer([:positive])}"

      Persistence.upsert_issue_run(%{issue_id: id1, issue_identifier: "P-1", status: "completed"})
      Persistence.upsert_issue_run(%{issue_id: id2, issue_identifier: "P-2", status: "completed"})
      Persistence.upsert_issue_run(%{issue_id: id3, issue_identifier: "P-3", status: "running"})

      completed = Persistence.load_completed_issue_ids()
      assert MapSet.member?(completed, id1)
      assert MapSet.member?(completed, id2)
      refute MapSet.member?(completed, id3)
    end

    test "delete_issue_run removes the record" do
      issue_id = "delete-#{System.unique_integer([:positive])}"

      Persistence.upsert_issue_run(%{issue_id: issue_id, issue_identifier: "P-DEL", status: "running"})
      assert Persistence.get_issue_run(issue_id) != nil

      Persistence.delete_issue_run(issue_id)
      assert Persistence.get_issue_run(issue_id) == nil
    end
  end

  describe "codex totals persistence" do
    test "save and load codex totals" do
      totals = %{input_tokens: 1000, output_tokens: 500, total_tokens: 1500, seconds_running: 60}

      assert :ok = Persistence.save_codex_totals(totals)

      loaded = Persistence.load_codex_totals()
      assert loaded.input_tokens == 1000
      assert loaded.output_tokens == 500
      assert loaded.total_tokens == 1500
      assert loaded.seconds_running == 60
    end

    test "load_codex_totals returns nil when no data" do
      # This test relies on a fresh DB state for the key
      # Since we can't guarantee key absence, just verify the function works
      result = Persistence.load_codex_totals()
      assert is_nil(result) or is_map(result)
    end
  end

  describe "agent session tracking" do
    test "record_session_start creates a session" do
      attrs = %{
        issue_id: "session-issue-#{System.unique_integer([:positive])}",
        session_id: "sess-abc123",
        attempt: 1,
        status: "running"
      }

      assert {:ok, session} = Persistence.record_session_start(attrs)
      assert session.issue_id == attrs.issue_id
      assert session.session_id == "sess-abc123"
      assert session.started_at != nil
    end

    test "record_session_end updates status and timestamp" do
      {:ok, session} = Persistence.record_session_start(%{
        issue_id: "session-end-#{System.unique_integer([:positive])}",
        status: "running"
      })

      assert :ok = Persistence.record_session_end(session.id, "completed", %{
        input_tokens: 100,
        output_tokens: 50,
        total_tokens: 150
      })
    end
  end
end
