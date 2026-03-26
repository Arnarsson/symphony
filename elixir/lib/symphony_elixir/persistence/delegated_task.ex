defmodule SymphonyElixir.Persistence.DelegatedTask do
  @moduledoc """
  Ecto schema for tasks delegated to Symphony via the REST API.

  External agents (like Eureka/OpenClaw) submit tasks through
  `POST /api/v1/delegate`. Tasks are persisted here and served
  to the orchestrator through the Delegation tracker adapter.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}

  schema "delegated_tasks" do
    field :external_id, :string
    field :title, :string
    field :description, :string
    field :repo_url, :string
    field :branch, :string
    field :status, :string, default: "queued"
    field :priority, :integer, default: 0
    field :callback_url, :string
    field :callback_secret, :string
    field :result, :string
    field :error, :string
    field :source, :string, default: "api"
    field :metadata, :string
    field :claimed_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:id, :title, :status]
  @optional_fields [
    :external_id, :description, :repo_url, :branch, :priority,
    :callback_url, :callback_secret, :result, :error, :source,
    :metadata, :claimed_at, :completed_at
  ]

  @valid_statuses ["queued", "claimed", "running", "completed", "failed", "cancelled"]

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(task, attrs) do
    task
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, @valid_statuses)
  end
end
