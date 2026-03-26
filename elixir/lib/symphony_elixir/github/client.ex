defmodule SymphonyElixir.GitHub.Client do
  @moduledoc """
  GitHub REST API client for fetching and managing issues.
  """

  require Logger
  alias SymphonyElixir.{Config, Linear.Issue}

  @api_base "https://api.github.com"
  @fuse_name :github_api
  @fuse_opts {{:standard, 5, 60_000}, {:reset, 30_000}}

  @spec fetch_candidate_issues() :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_candidate_issues do
    config = Config.settings!().tracker
    repo = config.project_slug
    active_states = config.active_states

    labels = active_states |> Enum.join(",")
    path = "/repos/#{repo}/issues?state=open&labels=#{URI.encode(labels)}&per_page=100&sort=created&direction=asc"

    case api_get(path) do
      {:ok, issues} when is_list(issues) ->
        {:ok, Enum.map(issues, &normalize_issue/1)}

      {:ok, _} ->
        {:error, :github_unexpected_response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec fetch_issues_by_states([String.t()]) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issues_by_states(states) do
    config = Config.settings!().tracker
    repo = config.project_slug
    labels = states |> Enum.join(",")
    path = "/repos/#{repo}/issues?state=open&labels=#{URI.encode(labels)}&per_page=100"

    case api_get(path) do
      {:ok, issues} when is_list(issues) ->
        {:ok, Enum.map(issues, &normalize_issue/1)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec fetch_issue_states_by_ids([String.t()]) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issue_states_by_ids(issue_ids) do
    config = Config.settings!().tracker
    repo = config.project_slug

    results =
      Enum.reduce_while(issue_ids, {:ok, []}, fn issue_id, {:ok, acc} ->
        # issue_id is the issue number as string
        path = "/repos/#{repo}/issues/#{issue_id}"

        case api_get(path) do
          {:ok, issue} when is_map(issue) ->
            {:cont, {:ok, [normalize_issue(issue) | acc]}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)

    case results do
      {:ok, issues} -> {:ok, Enum.reverse(issues)}
      error -> error
    end
  end

  @spec create_comment(String.t(), String.t()) :: :ok | {:error, term()}
  def create_comment(issue_number, body) do
    config = Config.settings!().tracker
    repo = config.project_slug
    path = "/repos/#{repo}/issues/#{issue_number}/comments"

    case api_post(path, %{body: body}) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec add_label(String.t(), String.t()) :: :ok | {:error, term()}
  def add_label(issue_number, label) do
    config = Config.settings!().tracker
    repo = config.project_slug
    path = "/repos/#{repo}/issues/#{issue_number}/labels"

    case api_post(path, %{labels: [label]}) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec close_issue(String.t()) :: :ok | {:error, term()}
  def close_issue(issue_number) do
    config = Config.settings!().tracker
    repo = config.project_slug
    path = "/repos/#{repo}/issues/#{issue_number}"

    case api_patch(path, %{state: "closed"}) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # -- API helpers --

  defp normalize_issue(gh_issue) when is_map(gh_issue) do
    labels =
      (gh_issue["labels"] || [])
      |> Enum.map(fn
        %{"name" => name} -> name
        label when is_binary(label) -> label
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)

    state =
      cond do
        gh_issue["state"] == "closed" -> "Done"
        true -> infer_state_from_labels(labels)
      end

    %Issue{
      id: to_string(gh_issue["number"]),
      identifier: "#{repo_short_name()}-#{gh_issue["number"]}",
      title: gh_issue["title"],
      description: gh_issue["body"],
      priority: 0,
      state: state,
      branch_name: nil,
      url: gh_issue["html_url"],
      assignee_id: get_in(gh_issue, ["assignee", "login"]),
      labels: labels,
      assigned_to_worker: true,
      created_at: parse_datetime(gh_issue["created_at"]),
      updated_at: parse_datetime(gh_issue["updated_at"])
    }
  end

  defp infer_state_from_labels(labels) do
    config = Config.settings!().tracker
    active_states = config.active_states

    Enum.find(active_states, "Todo", fn state ->
      Enum.member?(labels, state)
    end)
  end

  defp repo_short_name do
    Config.settings!().tracker.project_slug
    |> String.split("/")
    |> List.last()
    |> String.upcase()
    |> String.slice(0, 6)
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp api_get(path) do
    with_fuse(fn ->
      Req.get(url(path), headers: auth_headers(), connect_options: [timeout: 30_000], receive_timeout: 30_000)
      |> handle_response()
    end)
  end

  defp api_post(path, body) do
    with_fuse(fn ->
      Req.post(url(path), headers: auth_headers(), json: body, connect_options: [timeout: 30_000], receive_timeout: 30_000)
      |> handle_response()
    end)
  end

  defp api_patch(path, body) do
    with_fuse(fn ->
      Req.patch(url(path), headers: auth_headers(), json: body, connect_options: [timeout: 30_000], receive_timeout: 30_000)
      |> handle_response()
    end)
  end

  defp handle_response({:ok, %{status: status, body: body}}) when status in 200..299 do
    {:ok, body}
  end

  defp handle_response({:ok, %{status: 404}}) do
    {:error, :not_found}
  end

  defp handle_response({:ok, %{status: status, body: body}}) do
    Logger.warning("GitHub API error status=#{status} body=#{inspect(body, limit: 500)}")
    :fuse.melt(@fuse_name)
    {:error, {:github_api_status, status}}
  end

  defp handle_response({:error, reason}) do
    Logger.warning("GitHub API request failed: #{inspect(reason)}")
    :fuse.melt(@fuse_name)
    {:error, {:github_api_request, reason}}
  end

  defp with_fuse(fun) do
    case :fuse.ask(@fuse_name, :sync) do
      :ok -> fun.()
      :blown ->
        Logger.warning("GitHub API circuit breaker is open, skipping request")
        {:error, :circuit_breaker_open}
    end
  end

  defp url(path), do: @api_base <> path

  defp auth_headers do
    token = Config.settings!().tracker.api_key

    [
      {"Authorization", "Bearer #{token}"},
      {"Accept", "application/vnd.github+json"},
      {"X-GitHub-Api-Version", "2022-11-28"}
    ]
  end

  @doc false
  @spec install_fuse() :: :ok
  def install_fuse do
    :fuse.install(@fuse_name, @fuse_opts)
    :ok
  rescue
    _ -> :ok
  end
end
