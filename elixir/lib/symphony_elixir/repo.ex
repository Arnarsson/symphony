defmodule SymphonyElixir.Repo do
  @moduledoc """
  Ecto repository backed by SQLite for durable orchestrator state.
  """

  use Ecto.Repo,
    otp_app: :symphony_elixir,
    adapter: Ecto.Adapters.SQLite3
end
