defmodule SymphonyElixir.Repo.Migrations.CreateOrchestratorTables do
  use Ecto.Migration

  def change do
    create table(:issue_runs, primary_key: false) do
      add :issue_id, :string, primary_key: true
      add :issue_identifier, :string, null: false
      add :status, :string, null: false, default: "claimed"
      add :retry_attempt, :integer, default: 0
      add :last_error, :text
      add :worker_host, :string
      add :workspace_path, :string
      add :session_id, :string
      add :input_tokens, :integer, default: 0
      add :output_tokens, :integer, default: 0
      add :total_tokens, :integer, default: 0

      timestamps(type: :utc_datetime_usec)
    end

    create index(:issue_runs, [:status])
    create index(:issue_runs, [:issue_identifier])

    create table(:agent_sessions) do
      add :issue_id, :string, null: false
      add :session_id, :string
      add :attempt, :integer, default: 1
      add :status, :string, null: false, default: "running"
      add :input_tokens, :integer, default: 0
      add :output_tokens, :integer, default: 0
      add :total_tokens, :integer, default: 0
      add :turn_count, :integer, default: 0
      add :error, :text
      add :worker_host, :string
      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:agent_sessions, [:issue_id])
    create index(:agent_sessions, [:status])

    create table(:orchestrator_state, primary_key: false) do
      add :key, :string, primary_key: true
      add :value, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end
  end
end
