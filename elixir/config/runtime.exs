import Config

if config_env() == :prod do
  database_path =
    System.get_env("SYMPHONY_DATABASE_PATH") ||
      Path.join(System.get_env("HOME", "/tmp"), ".symphony/symphony.db")

  File.mkdir_p!(Path.dirname(database_path))

  config :symphony_elixir, SymphonyElixir.Repo,
    database: database_path,
    pool_size: 5,
    journal_mode: :wal

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      :crypto.strong_rand_bytes(64) |> Base.encode64() |> binary_part(0, 64)

  config :symphony_elixir, SymphonyElixirWeb.Endpoint,
    secret_key_base: secret_key_base
end
