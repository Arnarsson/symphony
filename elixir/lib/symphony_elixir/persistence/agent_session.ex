defmodule SymphonyElixir.Persistence.AgentSession do
  @moduledoc """
  Records agent session history for audit trail and analytics.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "agent_sessions" do
    field :issue_id, :string
    field :session_id, :string
    field :attempt, :integer, default: 1
    field :status, :string, default: "running"
    field :input_tokens, :integer, default: 0
    field :output_tokens, :integer, default: 0
    field :total_tokens, :integer, default: 0
    field :turn_count, :integer, default: 0
    field :error, :string
    field :worker_host, :string
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(session, attrs) do
    session
    |> cast(attrs, [
      :issue_id,
      :session_id,
      :attempt,
      :status,
      :input_tokens,
      :output_tokens,
      :total_tokens,
      :turn_count,
      :error,
      :worker_host,
      :started_at,
      :finished_at
    ])
    |> validate_required([:issue_id, :status])
    |> validate_inclusion(:status, ["running", "completed", "failed"])
  end
end
