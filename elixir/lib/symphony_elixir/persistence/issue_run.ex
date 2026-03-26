defmodule SymphonyElixir.Persistence.IssueRun do
  @moduledoc """
  Tracks per-issue orchestration state across restarts.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:issue_id, :string, autogenerate: false}

  schema "issue_runs" do
    field :issue_identifier, :string
    field :status, :string, default: "claimed"
    field :retry_attempt, :integer, default: 0
    field :last_error, :string
    field :worker_host, :string
    field :workspace_path, :string
    field :session_id, :string
    field :input_tokens, :integer, default: 0
    field :output_tokens, :integer, default: 0
    field :total_tokens, :integer, default: 0

    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(issue_run, attrs) do
    issue_run
    |> cast(attrs, [
      :issue_id,
      :issue_identifier,
      :status,
      :retry_attempt,
      :last_error,
      :worker_host,
      :workspace_path,
      :session_id,
      :input_tokens,
      :output_tokens,
      :total_tokens
    ])
    |> validate_required([:issue_id, :issue_identifier, :status])
    |> validate_inclusion(:status, ["claimed", "running", "completed", "retrying", "failed"])
  end
end
