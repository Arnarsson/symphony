defmodule SymphonyElixir.Delegation.Webhook do
  @moduledoc """
  Fires HTTP POST webhooks to notify external agents when delegated tasks complete.

  The callback URL and optional HMAC secret are stored on each `DelegatedTask`.
  Payloads are signed with HMAC-SHA256 when a `callback_secret` is present.
  """

  require Logger

  @spec notify_async(struct(), String.t()) :: :ok
  def notify_async(%{callback_url: nil}, _status), do: :ok
  def notify_async(%{callback_url: ""}, _status), do: :ok

  def notify_async(task, status) do
    Task.Supervisor.start_child(SymphonyElixir.TaskSupervisor, fn ->
      notify(task, status)
    end)

    :ok
  end

  @spec notify(struct(), String.t()) :: :ok | {:error, term()}
  def notify(%{callback_url: url} = task, status) when is_binary(url) and url != "" do
    payload = build_payload(task, status)
    body = Jason.encode!(payload)
    headers = build_headers(body, task.callback_secret)

    case Req.post(url, body: body, headers: headers, receive_timeout: 15_000, retry: :transient, max_retries: 3) do
      {:ok, %{status: status_code}} when status_code in 200..299 ->
        Logger.info("Delegation webhook delivered task=#{task.id} status=#{status} to #{url}")
        :ok

      {:ok, %{status: status_code}} ->
        Logger.warning("Delegation webhook rejected task=#{task.id} status=#{status_code} url=#{url}")
        {:error, {:http_error, status_code}}

      {:error, reason} ->
        Logger.warning("Delegation webhook failed task=#{task.id} reason=#{inspect(reason)} url=#{url}")
        {:error, reason}
    end
  end

  def notify(_, _), do: :ok

  defp build_payload(task, status) do
    %{
      event: "task.#{status}",
      task: %{
        id: task.id,
        external_id: task.external_id,
        title: task.title,
        status: status,
        result: task.result,
        error: task.error,
        source: task.source,
        completed_at: task.completed_at && DateTime.to_iso8601(task.completed_at),
        created_at: task.inserted_at && DateTime.to_iso8601(task.inserted_at)
      },
      timestamp: DateTime.to_iso8601(DateTime.utc_now())
    }
  end

  defp build_headers(body, secret) when is_binary(secret) and secret != "" do
    signature = :crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower)
    [{"content-type", "application/json"}, {"x-symphony-signature", "sha256=#{signature}"}]
  end

  defp build_headers(_body, _secret) do
    [{"content-type", "application/json"}]
  end
end
