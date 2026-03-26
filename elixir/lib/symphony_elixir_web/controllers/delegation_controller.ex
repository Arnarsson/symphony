defmodule SymphonyElixirWeb.DelegationController do
  @moduledoc """
  REST API for external agents to delegate tasks to Symphony.

  ## Endpoints

  - `POST /api/v1/delegate` — Submit a new task
  - `GET /api/v1/delegate/:id` — Check task status
  - `GET /api/v1/delegate` — List tasks (optional `?source=eureka` filter)
  - `DELETE /api/v1/delegate/:id` — Cancel a task

  ## Example: Eureka delegating a task

      POST /api/v1/delegate
      Authorization: Bearer <token>
      Content-Type: application/json

      {
        "title": "Implement user authentication",
        "description": "Add JWT-based auth to the /api/v1/users endpoint",
        "repo_url": "https://github.com/org/repo",
        "branch": "feature/auth",
        "priority": 2,
        "callback_url": "https://eureka.example.com/hooks/symphony",
        "callback_secret": "whsec_...",
        "source": "eureka",
        "external_id": "eureka-task-42",
        "metadata": {"labels": ["backend", "security"]}
      }
  """

  use Phoenix.Controller, formats: [:json]

  alias SymphonyElixir.Delegation

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, params) do
    attrs = %{
      title: params["title"],
      description: params["description"],
      repo_url: params["repo_url"],
      branch: params["branch"],
      priority: params["priority"] || 0,
      callback_url: params["callback_url"],
      callback_secret: params["callback_secret"],
      source: params["source"] || "api",
      external_id: params["external_id"],
      metadata: encode_metadata(params["metadata"]),
      status: "queued"
    }

    case Delegation.create_task(attrs) do
      {:ok, task} ->
        conn
        |> put_status(:created)
        |> json(%{
          ok: true,
          task: serialize_task(task)
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, errors: format_changeset_errors(changeset)})
    end
  end

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"id" => id}) do
    case Delegation.get_task(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{ok: false, error: "task not found"})

      task ->
        json(conn, %{ok: true, task: serialize_task(task)})
    end
  end

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, params) do
    opts = []
    opts = if params["source"], do: [{:source, params["source"]} | opts], else: opts
    opts = if params["limit"], do: [{:limit, String.to_integer(params["limit"])} | opts], else: opts

    tasks = Delegation.list_tasks(opts)
    json(conn, %{ok: true, tasks: Enum.map(tasks, &serialize_task/1)})
  end

  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(conn, %{"id" => id}) do
    case Delegation.cancel_task(id) do
      {:ok, task} ->
        json(conn, %{ok: true, task: serialize_task(task)})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{ok: false, error: "task not found"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, errors: format_changeset_errors(changeset)})
    end
  end

  defp serialize_task(task) do
    %{
      id: task.id,
      external_id: task.external_id,
      title: task.title,
      description: task.description,
      repo_url: task.repo_url,
      branch: task.branch,
      status: task.status,
      priority: task.priority,
      source: task.source,
      result: task.result,
      error: task.error,
      callback_url: task.callback_url,
      metadata: decode_metadata(task.metadata),
      claimed_at: task.claimed_at && DateTime.to_iso8601(task.claimed_at),
      completed_at: task.completed_at && DateTime.to_iso8601(task.completed_at),
      created_at: task.inserted_at && DateTime.to_iso8601(task.inserted_at),
      updated_at: task.updated_at && DateTime.to_iso8601(task.updated_at)
    }
  end

  defp encode_metadata(nil), do: nil
  defp encode_metadata(meta) when is_map(meta), do: Jason.encode!(meta)
  defp encode_metadata(meta) when is_binary(meta), do: meta

  defp decode_metadata(nil), do: nil
  defp decode_metadata(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, data} -> data
      _ -> nil
    end
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
