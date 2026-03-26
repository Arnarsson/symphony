import Config

config :symphony_elixir, SymphonyElixir.Repo,
  database: ":memory:",
  pool_size: 1,
  pool: Ecto.Adapters.SQL.Sandbox

config :logger, level: :warning
