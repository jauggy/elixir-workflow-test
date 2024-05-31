defmodule Teiserver.Telemetry.SimpleMatchEventTest do
  @moduledoc false
  use Teiserver.DataCase
  alias Teiserver.{Battle, Telemetry}
  alias Teiserver.TeiserverTestLib

  test "simple match events" do
    r = :rand.uniform(999_999_999)

    user = TeiserverTestLib.new_user("simple_match_event_user")

    {:ok, match} =
      Battle.create_match(%{
        uuid: ExULID.ULID.generate(),
        map: "red desert",
        data: %{},
        tags: %{},
        team_count: 2,
        team_size: 2,
        passworded: false,
        game_type: "Team",
        founder_id: user.id,
        founder_name: user.name,
        server_uuid: "#{r}",
        bots: %{},
        started: Timex.now() |> Timex.shift(minutes: -30),
        finished: Timex.now() |> Timex.shift(seconds: -30)
      })

    # Start by removing all match events
    query = "DELETE FROM telemetry_simple_match_events;"
    Ecto.Adapters.SQL.query(Repo, query, [])
    assert Telemetry.list_simple_match_events() |> Enum.count() == 0

    # Log the event
    {result, _} =
      Telemetry.log_simple_match_event(user.id, match.id, "match.simple_user_event-#{r}", 100)

    assert result == :ok

    assert Telemetry.list_simple_match_events() |> Enum.count() == 1
    assert Telemetry.list_simple_match_events(where: [user_id: user.id]) |> Enum.count() == 1
    assert Telemetry.list_simple_match_events(where: [match_id: match.id]) |> Enum.count() == 1

    # Ensure the match event types exist too
    type_list =
      Telemetry.list_simple_match_event_types()
      |> Enum.map(fn %{name: name} -> name end)

    assert Enum.member?(type_list, "match.simple_user_event-#{r}")
  end
end
