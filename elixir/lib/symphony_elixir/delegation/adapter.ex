defmodule SymphonyElixir.Delegation.Adapter do
  @moduledoc """
  Tracker adapter that serves delegated tasks from the API queue.

  External agents submit tasks via `POST /api/v1/delegate`.
  This adapter converts queued `DelegatedTask` records into
  `Linear.Issue` structs that the orchestrator can dispatch.
  """

  @behaviour SymphonyElixir.Tracker

  alias SymphonyElixir.Delegation
  alias SymphonyElixir.Linear.Issue

  @impl true
  def fetch_candidate_issues do
    tasks = Delegation.list_tasks_by_status("queued")

    issues =
      Enum.map(tasks, fn task ->
        %Issue{
          id: task.id,
          identifier: task.external_id || task.id,
          title: task.title,
          description: task.description || "",
          priority: task.priority,
          state: "queued",
          branch_name: task.branch,
          url: task.callback_url,
          labels: [task.source || "api"],
          assigned_to_worker: true,
          created_at: task.inserted_at
        }
      end)

    {:ok, issues}
  end

  @impl true
  def fetch_issues_by_states(states) do
    # Map our statuses to task DB statuses
    tasks =
      states
      |> Enum.flat_map(&Delegation.list_tasks_by_status/1)
      |> Enum.uniq_by(& &1.id)

    issues = Enum.map(tasks, &task_to_issue/1)
    {:ok, issues}
  end

  @impl true
  def fetch_issue_states_by_ids(issue_ids) do
    states =
      issue_ids
      |> Enum.map(fn id ->
        case Delegation.get_task(id) do
          nil -> {id, "cancelled"}
          task -> {id, task.status}
        end
      end)
      |> Map.new()

    {:ok, states}
  end

  @impl true
  def create_comment(issue_id, body) do
    case Delegation.get_task(issue_id) do
      nil ->
        {:error, :not_found}

      task ->
        # Append comment to task metadata as JSON
        existing = decode_metadata(task.metadata)
        comments = Map.get(existing, "comments", [])
        updated = Map.put(existing, "comments", comments ++ [%{"body" => body, "at" => DateTime.to_iso8601(DateTime.utc_now())}])
        Delegation.update_task(task, %{metadata: Jason.encode!(updated)})
        :ok
    end
  end

  @impl true
  def update_issue_state(issue_id, state_name) do
    case Delegation.get_task(issue_id) do
      nil ->
        {:error, :not_found}

      task ->
        new_status = normalize_state(state_name)
        attrs = %{status: new_status}

        attrs =
          if new_status in ["completed", "failed"] do
            Map.put(attrs, :completed_at, DateTime.utc_now())
          else
            attrs
          end

        Delegation.update_task(task, attrs)

        # Fire completion webhook if applicable
        if new_status in ["completed", "failed"] do
          Delegation.Webhook.notify_async(task, new_status)
        end

        :ok
    end
  end

  defp task_to_issue(task) do
    %Issue{
      id: task.id,
      identifier: task.external_id || task.id,
      title: task.title,
      description: task.description || "",
      priority: task.priority,
      state: task.status,
      branch_name: task.branch,
      url: task.callback_url,
      labels: [task.source || "api"],
      assigned_to_worker: true,
      created_at: task.inserted_at
    }
  end

  defp normalize_state("Done"), do: "completed"
  defp normalize_state("In Progress"), do: "running"
  defp normalize_state("Todo"), do: "queued"
  defp normalize_state(state), do: String.downcase(state)

  defp decode_metadata(nil), do: %{}
  defp decode_metadata(""), do: %{}

  defp decode_metadata(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, map} when is_map(map) -> map
      _ -> %{}
    end
  end
end
