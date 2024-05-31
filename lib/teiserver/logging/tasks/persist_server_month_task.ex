defmodule Teiserver.Logging.Tasks.PersistServerMonthTask do
  @moduledoc false
  use Oban.Worker, queue: :teiserver
  alias Teiserver.Logging
  alias Teiserver.Logging.ServerDayLogLib
  import Ecto.Query, warn: false

  @impl Oban.Worker
  @spec perform(any) :: :ok
  def perform(_) do
    log =
      case Logging.get_last_server_month_log() do
        nil ->
          perform_first_time()

        {year, month} ->
          {y, m} = next_month({year, month})
          perform_standard(y, m)
      end

    if log != nil do
      %{}
      |> Teiserver.Logging.Tasks.PersistServerMonthTask.new()
      |> Oban.insert()
    end

    :ok
  end

  # For when there are no existing logs
  # we need to ensure the earliest log is from last month, not this month
  defp perform_first_time() do
    first_logs =
      Logging.list_server_day_logs(
        order: "Oldest first",
        limit: 1
      )

    case first_logs do
      [log] ->
        today = Timex.today()

        if log.date.year < today.year or log.date.month < today.month do
          logs =
            Logging.list_server_day_logs(
              search: [
                start_date: Timex.beginning_of_month(log.date),
                end_date: Timex.end_of_month(log.date)
              ]
            )

          user_activity_logs =
            Logging.list_user_activity_day_logs(
              search: [
                start_date: Timex.beginning_of_month(log.date),
                end_date: Timex.end_of_month(log.date)
              ]
            )

          data =
            logs
            |> Enum.zip(user_activity_logs)
            |> ServerDayLogLib.aggregate_day_logs()

          {:ok, _} =
            Logging.create_server_month_log(%{
              year: log.date.year,
              month: log.date.month,
              date: Timex.Date.new!(log.date.year, log.date.month, 1),
              data: data
            })
        end

      _ ->
        nil
    end
  end

  # For when we have an existing log
  defp perform_standard(year, month) do
    today = Timex.today()

    if year < today.year or month < today.month do
      now = Timex.Date.new!(year, month, 1)

      logs =
        Logging.list_server_day_logs(
          search: [
            start_date: Timex.beginning_of_month(now),
            end_date: Timex.end_of_month(now)
          ]
        )

      user_activity_logs =
        Logging.list_user_activity_day_logs(
          search: [
            start_date: Timex.beginning_of_month(now),
            end_date: Timex.end_of_month(now)
          ]
        )

      data =
        logs
        |> Enum.zip(user_activity_logs)
        |> ServerDayLogLib.aggregate_day_logs()

      {:ok, _} =
        Logging.create_server_month_log(%{
          year: year,
          month: month,
          date: now,
          data: data
        })
    else
      nil
    end
  end

  @spec month_so_far() :: map()
  def month_so_far() do
    now = Timex.now()

    user_activity_logs =
      Logging.list_user_activity_day_logs(
        search: [
          start_date: Timex.beginning_of_month(now)
        ]
      )

    Logging.list_server_day_logs(
      search: [
        start_date: Timex.beginning_of_month(now)
      ]
    )
    |> Enum.zip(user_activity_logs)
    |> ServerDayLogLib.aggregate_day_logs()
    |> Jason.encode!()
    |> Jason.decode!()

    # We encode and decode so it's the same format as in the database
  end

  defp next_month({year, 12}), do: {year + 1, 1}
  defp next_month({year, month}), do: {year, month + 1}
end
