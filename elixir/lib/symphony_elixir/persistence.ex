defmodule SymphonyElixir.Persistence do
  @moduledoc """
  Durable state persistence for the orchestrator.

  Provides functions to save and restore orchestrator state across restarts,
  record agent session history, and track issue lifecycle.
  """

  import Ecto.Query
  require Logger

  alias SymphonyElixir.Repo
  alias SymphonyElixir.Persistence.{AgentSession, IssueRun}

  # -- Issue Run tracking --

  @spec upsert_issue_run(map()) :: {:ok, IssueRun.t()} | {:error, Ecto.Changeset.t()}
  def upsert_issue_run(attrs) when is_map(attrs) do
    case Repo.get(IssueRun, attrs[:issue_id] || attrs["issue_id"]) do
      nil -> %IssueRun{}
      existing -> existing
    end
    |> IssueRun.changeset(attrs)
    |> Repo.insert_or_update()
  end

  @spec mark_issue_status(String.t(), String.t(), map()) :: :ok
  def mark_issue_status(issue_id, status, extra \\ %{}) do
    attrs = Map.merge(extra, %{issue_id: issue_id, status: status})

    case upsert_issue_run(attrs) do
      {:ok, _} -> :ok
      {:error, changeset} ->
        Logger.warning("Failed to persist issue status: #{inspect(changeset.errors)}")
        :ok
    end
  end

  @spec mark_issue_completed(String.t()) :: :ok
  def mark_issue_completed(issue_id) do
    mark_issue_status(issue_id, "completed")
  end

  @spec mark_issue_retrying(String.t(), integer(), String.t() | nil) :: :ok
  def mark_issue_retrying(issue_id, attempt, error \\ nil) do
    mark_issue_status(issue_id, "retrying", %{retry_attempt: attempt, last_error: error})
  end

  @spec delete_issue_run(String.t()) :: :ok
  def delete_issue_run(issue_id) do
    Repo.delete_all(from(r in IssueRun, where: r.issue_id == ^issue_id))
    :ok
  end

  @spec get_issue_run(String.t()) :: IssueRun.t() | nil
  def get_issue_run(issue_id) do
    Repo.get(IssueRun, issue_id)
  end

  @spec list_issue_runs_by_status(String.t()) :: [IssueRun.t()]
  def list_issue_runs_by_status(status) do
    Repo.all(from(r in IssueRun, where: r.status == ^status))
  end

  @spec load_completed_issue_ids() :: MapSet.t()
  def load_completed_issue_ids do
    from(r in IssueRun, where: r.status == "completed", select: r.issue_id)
    |> Repo.all()
    |> MapSet.new()
  end

  @spec load_retry_state() :: map()
  def load_retry_state do
    from(r in IssueRun, where: r.status == "retrying")
    |> Repo.all()
    |> Map.new(fn run ->
      {run.issue_id, %{
        attempt: run.retry_attempt,
        identifier: run.issue_identifier,
        error: run.last_error,
        worker_host: run.worker_host,
        workspace_path: run.workspace_path
      }}
    end)
  end

  # -- Agent Session tracking --

  @spec record_session_start(map()) :: {:ok, AgentSession.t()} | {:error, Ecto.Changeset.t()}
  def record_session_start(attrs) do
    %AgentSession{}
    |> AgentSession.changeset(Map.put(attrs, :started_at, DateTime.utc_now()))
    |> Repo.insert()
  end

  @spec record_session_end(integer(), String.t(), map()) :: :ok
  def record_session_end(session_db_id, status, attrs \\ %{}) do
    case Repo.get(AgentSession, session_db_id) do
      nil -> :ok
      session ->
        session
        |> AgentSession.changeset(Map.merge(attrs, %{status: status, finished_at: DateTime.utc_now()}))
        |> Repo.update()

        :ok
    end
  end

  @spec update_session_tokens(integer(), map()) :: :ok
  def update_session_tokens(session_db_id, token_attrs) do
    case Repo.get(AgentSession, session_db_id) do
      nil -> :ok
      session ->
        session
        |> AgentSession.changeset(token_attrs)
        |> Repo.update()

        :ok
    end
  end

  # -- Orchestrator aggregate state --

  @spec save_agent_totals(map()) :: :ok
  def save_agent_totals(totals) when is_map(totals) do
    save_state("agent_totals", Jason.encode!(totals))
  end

  @doc "Legacy alias for backwards compatibility with existing DB data."
  @spec save_codex_totals(map()) :: :ok
  def save_codex_totals(totals), do: save_agent_totals(totals)

  @spec load_agent_totals() :: map() | nil
  def load_agent_totals do
    case load_state("agent_totals") || load_state("codex_totals") do
      nil -> nil
      json -> Jason.decode!(json, keys: :atoms)
    end
  end

  @spec save_state(String.t(), String.t()) :: :ok
  defp save_state(key, value) do
    now = DateTime.utc_now()

    Repo.insert!(
      %{key: key, value: value, inserted_at: now, updated_at: now},
      on_conflict: [set: [value: value, updated_at: now]],
      conflict_target: :key,
      source: "orchestrator_state"
    )

    :ok
  rescue
    e ->
      Logger.warning("Failed to save orchestrator state #{key}: #{inspect(e)}")
      :ok
  end

  @spec load_state(String.t()) :: String.t() | nil
  defp load_state(key) do
    from(s in "orchestrator_state", where: s.key == ^key, select: s.value)
    |> Repo.one()
  rescue
    _ -> nil
  end
end
