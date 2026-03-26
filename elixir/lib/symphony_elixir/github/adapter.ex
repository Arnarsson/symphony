defmodule SymphonyElixir.GitHub.Adapter do
  @moduledoc """
  GitHub Issues tracker adapter.

  Maps GitHub Issues to Symphony's tracker interface using labels
  as state indicators. Configure via WORKFLOW.md:

      tracker:
        kind: github
        project_slug: "owner/repo"
        api_key: "$GITHUB_TOKEN"
        active_states: ["Todo", "In Progress"]
        terminal_states: ["Done", "Cancelled"]
  """

  @behaviour SymphonyElixir.Tracker

  alias SymphonyElixir.GitHub.Client

  @impl true
  @spec fetch_candidate_issues() :: {:ok, [term()]} | {:error, term()}
  def fetch_candidate_issues, do: Client.fetch_candidate_issues()

  @impl true
  @spec fetch_issues_by_states([String.t()]) :: {:ok, [term()]} | {:error, term()}
  def fetch_issues_by_states(states), do: Client.fetch_issues_by_states(states)

  @impl true
  @spec fetch_issue_states_by_ids([String.t()]) :: {:ok, [term()]} | {:error, term()}
  def fetch_issue_states_by_ids(issue_ids), do: Client.fetch_issue_states_by_ids(issue_ids)

  @impl true
  @spec create_comment(String.t(), String.t()) :: :ok | {:error, term()}
  def create_comment(issue_id, body), do: Client.create_comment(issue_id, body)

  @impl true
  @spec update_issue_state(String.t(), String.t()) :: :ok | {:error, term()}
  def update_issue_state(issue_id, state_name) do
    case String.downcase(state_name) do
      state when state in ["done", "closed", "cancelled", "canceled"] ->
        Client.close_issue(issue_id)

      _ ->
        Client.add_label(issue_id, state_name)
    end
  end
end
