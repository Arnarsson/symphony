defmodule SymphonyElixir.Delegation do
  @moduledoc """
  Context module for managing delegated tasks.

  External agents (Eureka, OpenClaw, etc.) submit tasks via the
  delegation API. Tasks are queued in SQLite and served to the
  orchestrator through `Delegation.Adapter`.
  """

  import Ecto.Query

  alias SymphonyElixir.Persistence.DelegatedTask
  alias SymphonyElixir.Repo

  @spec create_task(map()) :: {:ok, DelegatedTask.t()} | {:error, Ecto.Changeset.t()}
  def create_task(attrs) do
    id = attrs[:id] || attrs["id"] || generate_id()
    attrs = Map.put(attrs, :id, id)

    %DelegatedTask{}
    |> DelegatedTask.changeset(attrs)
    |> Repo.insert()
  end

  @spec get_task(String.t()) :: DelegatedTask.t() | nil
  def get_task(id) do
    Repo.get(DelegatedTask, id)
  end

  @spec get_task_by_external_id(String.t()) :: DelegatedTask.t() | nil
  def get_task_by_external_id(external_id) do
    Repo.one(from t in DelegatedTask, where: t.external_id == ^external_id, limit: 1)
  end

  @spec update_task(DelegatedTask.t(), map()) :: {:ok, DelegatedTask.t()} | {:error, Ecto.Changeset.t()}
  def update_task(%DelegatedTask{} = task, attrs) do
    task
    |> DelegatedTask.changeset(attrs)
    |> Repo.update()
  end

  @spec list_tasks_by_status(String.t()) :: [DelegatedTask.t()]
  def list_tasks_by_status(status) do
    from(t in DelegatedTask,
      where: t.status == ^status,
      order_by: [desc: :priority, asc: :inserted_at]
    )
    |> Repo.all()
  end

  @spec list_tasks(keyword()) :: [DelegatedTask.t()]
  def list_tasks(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    source = Keyword.get(opts, :source)

    query = from(t in DelegatedTask, order_by: [desc: :inserted_at], limit: ^limit)

    query =
      if source do
        from(t in query, where: t.source == ^source)
      else
        query
      end

    Repo.all(query)
  end

  @spec cancel_task(String.t()) :: {:ok, DelegatedTask.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def cancel_task(id) do
    case get_task(id) do
      nil -> {:error, :not_found}
      task -> update_task(task, %{status: "cancelled", completed_at: DateTime.utc_now()})
    end
  end

  @spec mark_claimed(String.t()) :: {:ok, DelegatedTask.t()} | {:error, term()}
  def mark_claimed(id) do
    case get_task(id) do
      nil -> {:error, :not_found}
      task -> update_task(task, %{status: "claimed", claimed_at: DateTime.utc_now()})
    end
  end

  @spec mark_completed(String.t(), String.t() | nil) :: {:ok, DelegatedTask.t()} | {:error, term()}
  def mark_completed(id, result \\ nil) do
    case get_task(id) do
      nil -> {:error, :not_found}
      task -> update_task(task, %{status: "completed", result: result, completed_at: DateTime.utc_now()})
    end
  end

  @spec mark_failed(String.t(), String.t() | nil) :: {:ok, DelegatedTask.t()} | {:error, term()}
  def mark_failed(id, error \\ nil) do
    case get_task(id) do
      nil -> {:error, :not_found}
      task -> update_task(task, %{status: "failed", error: error, completed_at: DateTime.utc_now()})
    end
  end

  defp generate_id do
    "task_" <> Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
  end
end
