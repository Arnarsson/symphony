defmodule SymphonyElixir.DelegationTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Delegation
  alias SymphonyElixir.Delegation.Adapter
  alias SymphonyElixir.Persistence.DelegatedTask

  setup do
    # Clean up delegated_tasks between tests
    SymphonyElixir.Repo.delete_all(DelegatedTask)
    :ok
  end

  describe "create_task/1" do
    test "creates a task with required fields" do
      attrs = %{title: "Fix authentication bug", description: "JWT tokens expire too fast"}

      assert {:ok, task} = Delegation.create_task(attrs)
      assert task.title == "Fix authentication bug"
      assert task.description == "JWT tokens expire too fast"
      assert task.status == "queued"
      assert task.id =~ ~r/^task_/
    end

    test "creates a task with all fields" do
      attrs = %{
        title: "Implement search",
        description: "Add full-text search to API",
        repo_url: "https://github.com/org/repo",
        branch: "feature/search",
        priority: 3,
        callback_url: "https://eureka.example.com/hooks",
        callback_secret: "whsec_test123",
        source: "eureka",
        external_id: "eureka-42"
      }

      assert {:ok, task} = Delegation.create_task(attrs)
      assert task.repo_url == "https://github.com/org/repo"
      assert task.branch == "feature/search"
      assert task.priority == 3
      assert task.callback_url == "https://eureka.example.com/hooks"
      assert task.source == "eureka"
      assert task.external_id == "eureka-42"
    end

    test "rejects task without title" do
      assert {:error, changeset} = Delegation.create_task(%{description: "no title"})
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "get_task/1" do
    test "returns task by id" do
      {:ok, task} = Delegation.create_task(%{title: "Test task"})
      assert found = Delegation.get_task(task.id)
      assert found.id == task.id
    end

    test "returns nil for unknown id" do
      assert is_nil(Delegation.get_task("nonexistent"))
    end
  end

  describe "get_task_by_external_id/1" do
    test "returns task by external_id" do
      {:ok, _} = Delegation.create_task(%{title: "Test", external_id: "ext-99"})
      assert found = Delegation.get_task_by_external_id("ext-99")
      assert found.external_id == "ext-99"
    end
  end

  describe "list_tasks_by_status/1" do
    test "returns tasks filtered by status" do
      {:ok, _} = Delegation.create_task(%{title: "Queued 1"})
      {:ok, t2} = Delegation.create_task(%{title: "Queued 2"})
      Delegation.mark_claimed(t2.id)

      queued = Delegation.list_tasks_by_status("queued")
      claimed = Delegation.list_tasks_by_status("claimed")

      assert length(queued) == 1
      assert length(claimed) == 1
      assert hd(claimed).id == t2.id
    end
  end

  describe "lifecycle operations" do
    test "mark_claimed/1 transitions to claimed" do
      {:ok, task} = Delegation.create_task(%{title: "Claim me"})
      assert {:ok, claimed} = Delegation.mark_claimed(task.id)
      assert claimed.status == "claimed"
      assert claimed.claimed_at != nil
    end

    test "mark_completed/2 transitions to completed with result" do
      {:ok, task} = Delegation.create_task(%{title: "Complete me"})
      assert {:ok, completed} = Delegation.mark_completed(task.id, "PR #42 merged")
      assert completed.status == "completed"
      assert completed.result == "PR #42 merged"
      assert completed.completed_at != nil
    end

    test "mark_failed/2 transitions to failed with error" do
      {:ok, task} = Delegation.create_task(%{title: "Fail me"})
      assert {:ok, failed} = Delegation.mark_failed(task.id, "Build failed")
      assert failed.status == "failed"
      assert failed.error == "Build failed"
      assert failed.completed_at != nil
    end

    test "cancel_task/1 transitions to cancelled" do
      {:ok, task} = Delegation.create_task(%{title: "Cancel me"})
      assert {:ok, cancelled} = Delegation.cancel_task(task.id)
      assert cancelled.status == "cancelled"
    end

    test "operations return error for missing tasks" do
      assert {:error, :not_found} = Delegation.mark_claimed("nope")
      assert {:error, :not_found} = Delegation.mark_completed("nope")
      assert {:error, :not_found} = Delegation.mark_failed("nope")
      assert {:error, :not_found} = Delegation.cancel_task("nope")
    end
  end

  describe "Delegation.Adapter" do
    test "fetch_candidate_issues returns queued tasks as Issue structs" do
      {:ok, _} = Delegation.create_task(%{title: "API task", source: "eureka", priority: 2})

      assert {:ok, issues} = Adapter.fetch_candidate_issues()
      assert length(issues) == 1

      issue = hd(issues)
      assert issue.title == "API task"
      assert issue.priority == 2
      assert issue.state == "queued"
      assert "eureka" in issue.labels
    end

    test "fetch_issue_states_by_ids returns status map" do
      {:ok, t1} = Delegation.create_task(%{title: "Task 1"})
      {:ok, t2} = Delegation.create_task(%{title: "Task 2"})
      Delegation.mark_claimed(t2.id)

      assert {:ok, states} = Adapter.fetch_issue_states_by_ids([t1.id, t2.id, "missing"])
      assert states[t1.id] == "queued"
      assert states[t2.id] == "claimed"
      assert states["missing"] == "cancelled"
    end

    test "update_issue_state changes task status" do
      {:ok, task} = Delegation.create_task(%{title: "State test"})
      assert :ok = Adapter.update_issue_state(task.id, "Done")

      updated = Delegation.get_task(task.id)
      assert updated.status == "completed"
    end

    test "create_comment appends to metadata" do
      {:ok, task} = Delegation.create_task(%{title: "Comment test"})
      assert :ok = Adapter.create_comment(task.id, "Agent started working")

      updated = Delegation.get_task(task.id)
      meta = Jason.decode!(updated.metadata)
      assert length(meta["comments"]) == 1
      assert hd(meta["comments"])["body"] == "Agent started working"
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
