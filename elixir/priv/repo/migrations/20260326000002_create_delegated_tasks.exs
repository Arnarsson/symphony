defmodule SymphonyElixir.Repo.Migrations.CreateDelegatedTasks do
  use Ecto.Migration

  def change do
    create table(:delegated_tasks, primary_key: false) do
      add :id, :string, primary_key: true
      add :external_id, :string
      add :title, :string, null: false
      add :description, :text
      add :repo_url, :string
      add :branch, :string
      add :status, :string, null: false, default: "queued"
      add :priority, :integer, default: 0
      add :callback_url, :string
      add :callback_secret, :string
      add :result, :text
      add :error, :text
      add :source, :string, default: "api"
      add :metadata, :text
      add :claimed_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:delegated_tasks, [:status])
    create index(:delegated_tasks, [:external_id])
    create index(:delegated_tasks, [:source])
  end
end
