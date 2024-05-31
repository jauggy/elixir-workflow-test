defmodule Teiserver.Coordinator.BalanceServerTest do
  @moduledoc false
  use Teiserver.ServerCase, async: false
  alias Teiserver.Account.ClientLib
  alias Teiserver.Game.MatchRatingLib
  alias Teiserver.{Account, Lobby, Battle, CacheUser, Client, Coordinator}
  alias Teiserver.Coordinator.ConsulServer

  import Teiserver.TeiserverTestLib,
    only: [
      tachyon_auth_setup: 0,
      _tachyon_send: 2,
      _tachyon_recv: 1,
      _tachyon_recv_until: 1,
      tachyon_auth_setup: 1,
      new_user: 1
    ]

  setup do
    Coordinator.start_coordinator()
    %{socket: hsocket, user: host} = tachyon_auth_setup()
    %{socket: psocket, user: player} = tachyon_auth_setup()

    # User needs to be a moderator (at this time) to start/stop Coordinator mode
    CacheUser.update_user(%{host | roles: ["Moderator"]})
    ClientLib.refresh_client(host.id)

    lobby_data = %{
      cmd: "c.lobby.create",
      name: "Coordinator #{:rand.uniform(999_999_999)}",
      nattype: "none",
      port: 1234,
      game_hash: "string_of_characters",
      map_hash: "string_of_characters",
      map_name: "koom valley",
      game_name: "BAR",
      engine_name: "spring-105",
      engine_version: "105.1.2.3",
      settings: %{
        max_players: 16
      }
    }

    data = %{cmd: "c.lobby.create", lobby: lobby_data}
    _tachyon_send(hsocket, data)
    [reply] = _tachyon_recv(hsocket)
    lobby_id = reply["lobby"]["id"]

    # Player needs to be added to the battle
    Lobby.add_user_to_battle(player.id, lobby_id, "script_password")
    player_client = Account.get_client_by_id(player.id)
    Client.update(%{player_client | player: true}, :client_updated_battlestatus)

    # Add user message
    _tachyon_recv_until(hsocket)

    # Battlestatus message
    _tachyon_recv_until(hsocket)

    {:ok, hsocket: hsocket, psocket: psocket, host: host, player: player, lobby_id: lobby_id}
  end

  defp make_rating(userid, rating_type_id, rating_value) do
    {:ok, _} =
      Account.create_rating(%{
        user_id: userid,
        rating_type_id: rating_type_id,
        rating_value: rating_value,
        skill: rating_value,
        uncertainty: 0,
        leaderboard_rating: rating_value,
        last_updated: Timex.now()
      })
  end

  test "server balance - simple", %{
    lobby_id: lobby_id,
    host: _host,
    psocket: _psocket,
    player: player
  } do
    # We don't want to use the player we start with, we want to number our players specifically
    Lobby.remove_user_from_any_lobby(player.id)

    %{user: u1} = ps1 = new_user("Team_Arbiter") |> tachyon_auth_setup()
    %{user: u2} = ps2 = new_user("Team_Brute") |> tachyon_auth_setup()
    %{user: u3} = ps3 = new_user("Team_Calamity") |> tachyon_auth_setup()
    %{user: u4} = ps4 = new_user("Team_Destroyer") |> tachyon_auth_setup()
    %{user: u5} = ps5 = new_user("Team_Eagle") |> tachyon_auth_setup()
    %{user: u6} = ps6 = new_user("Team_Fury") |> tachyon_auth_setup()
    %{user: u7} = ps7 = new_user("Team_Garpike") |> tachyon_auth_setup()
    %{user: u8} = ps8 = new_user("Team_Hound") |> tachyon_auth_setup()

    # Sleep to allow the users to be correctly added, otherwise we get PK errors we'd not
    # get in prod
    :timer.sleep(1000)

    rating_type_id = MatchRatingLib.rating_type_name_lookup()["Team"]

    [ps1, ps2, ps3, ps4, ps5, ps6, ps7, ps8]
    |> Enum.each(fn %{user: user, socket: socket} ->
      Lobby.force_add_user_to_lobby(user.id, lobby_id)
      # Need the sleep to ensure they all get added to the battle
      :timer.sleep(50)
      _tachyon_send(socket, %{cmd: "c.lobby.update_status", client: %{player: true, ready: true}})
    end)

    # Create some ratings
    # higher numbered players have higher ratings
    make_rating(u1.id, rating_type_id, 20)
    make_rating(u2.id, rating_type_id, 25)
    make_rating(u3.id, rating_type_id, 30)
    make_rating(u4.id, rating_type_id, 35)
    make_rating(u5.id, rating_type_id, 36)
    make_rating(u6.id, rating_type_id, 38)
    make_rating(u7.id, rating_type_id, 47)
    make_rating(u8.id, rating_type_id, 50)

    # Wait for everybody to get added to the room
    :timer.sleep(500)

    consul_state = Coordinator.call_consul(lobby_id, :get_all)
    max_player_count = ConsulServer.get_max_player_count(consul_state)
    assert max_player_count >= 8

    assert Battle.list_lobby_players(lobby_id) |> Enum.count() == 8

    opts = [
      shuffle_first_pick: false,
      fuzz_multiplier: 0
    ]

    team_count = 2

    balance_result =
      Coordinator.call_balancer(lobby_id, {
        :make_balance,
        team_count,
        opts
      })

    assert balance_result.team_players[1] == [u8.id, u5.id, u3.id, u2.id]
    assert balance_result.team_players[2] == [u7.id, u6.id, u4.id, u1.id]
    assert balance_result.deviation == 1
    assert balance_result.ratings == %{1 => 141.0, 2 => 140.0}
    assert Battle.get_lobby_balance_mode(lobby_id) == :solo

    # It caches so calling it with the same settings should result in the same value
    assert Coordinator.call_balancer(lobby_id, {
             :make_balance,
             team_count,
             opts
           }) == balance_result

    # Now if we do it again but with groups allowed it should be the same results but
    # with grouped set to true
    # we set the opts here rather than using the defaults because if the defaults change it will
    # break the test
    opts = [
      shuffle_first_pick: false,
      allow_groups: true,
      mean_diff_max: 15,
      stddev_diff_max: 10,
      rating_lower_boundary: 5,
      rating_upper_boundary: 5,
      max_deviation: 10,
      fuzz_multiplier: 0
    ]

    grouped_balance_result =
      Coordinator.call_balancer(lobby_id, {
        :make_balance,
        team_count,
        opts
      })

    assert grouped_balance_result.team_players[1] == [u8.id, u5.id, u3.id, u2.id]
    assert grouped_balance_result.team_players[2] == [u7.id, u6.id, u4.id, u1.id]
    assert grouped_balance_result.deviation == 1
    assert grouped_balance_result.ratings == %{1 => 141.0, 2 => 140.0}
    assert Battle.get_lobby_balance_mode(lobby_id) == :grouped
    assert grouped_balance_result.hash != balance_result.hash

    # Party time, we start with the two highest rated players being put on the same team
    high_party = Account.create_party(u8.id)
    Account.move_client_to_party(u7.id, high_party.id)

    # Sleep so we don't get a cached list of players when calculating the balance
    :timer.sleep(520)

    party_balance_result =
      Coordinator.call_balancer(lobby_id, {
        :make_balance,
        team_count,
        opts
      })

    # First things first, it should be a different hash
    refute party_balance_result.hash == balance_result.hash

    assert party_balance_result.team_players[1] == [u7.id, u8.id, u3.id, u1.id]
    assert party_balance_result.team_players[2] == [u6.id, u4.id, u5.id, u2.id]
    assert party_balance_result.ratings == %{1 => 147.0, 2 => 134.0}
    assert party_balance_result.deviation == 9
    assert party_balance_result.balance_mode == :grouped
    assert Battle.get_lobby_balance_mode(lobby_id) == :grouped

    assert party_balance_result.logs == [
             "Group matching",
             "> Grouped: Team_Garpike, Team_Hound",
             "--- Rating sum: 97.0",
             "--- Rating Mean: 48.5",
             "--- Rating Stddev: 1.5",
             "> Grouped: Team_Fury, Team_Destroyer",
             "--- Rating sum: 73.0",
             "--- Rating Mean: 36.5",
             "--- Rating Stddev: 1.5",
             "End of pairing",
             "Group picked Team_Garpike, Team_Hound for team 1, adding 97.0 points for new total of 97.0",
             "Group picked Team_Fury, Team_Destroyer for team 2, adding 73.0 points for new total of 73.0",
             "Picked Team_Eagle for team 2, adding 36.0 points for new total of 109.0",
             "Picked Team_Calamity for team 1, adding 30.0 points for new total of 127.0",
             "Picked Team_Brute for team 2, adding 25.0 points for new total of 134.0",
             "Picked Team_Arbiter for team 1, adding 20.0 points for new total of 147.0"
           ]

    # Now make an unfair party
    Account.move_client_to_party(u6.id, high_party.id)
    Account.move_client_to_party(u5.id, high_party.id)

    :timer.sleep(520)

    opts = [
      shuffle_first_pick: false,
      allow_groups: true,
      mean_diff_max: 20,
      stddev_diff_max: 10,
      rating_lower_boundary: 5,
      rating_upper_boundary: 5,
      max_deviation: 10,
      fuzz_multiplier: 0
    ]

    party_balance_result =
      Coordinator.call_balancer(lobby_id, {
        :make_balance,
        team_count,
        opts
      })

    # First things first, it should be a different hash
    refute party_balance_result.hash == balance_result.hash

    # Results should be the same as the first part of the test but with mode set to solo
    assert Battle.get_lobby_balance_mode(lobby_id) == :solo
    assert party_balance_result.balance_mode == :solo
    assert party_balance_result.team_players[1] == [u8.id, u5.id, u3.id, u2.id]
    assert party_balance_result.team_players[2] == [u7.id, u6.id, u4.id, u1.id]
    assert party_balance_result.ratings == %{1 => 141.0, 2 => 140.0}
    assert party_balance_result.deviation == 1

    assert party_balance_result.logs == [
             "Tried grouped mode, got a deviation of 36 and reverted to solo mode",
             "Picked Team_Hound for team 1, adding 50.0 points for new total of 50.0",
             "Picked Team_Garpike for team 2, adding 47.0 points for new total of 47.0",
             "Picked Team_Fury for team 2, adding 38.0 points for new total of 85.0",
             "Picked Team_Eagle for team 1, adding 36.0 points for new total of 86.0",
             "Picked Team_Destroyer for team 2, adding 35.0 points for new total of 120.0",
             "Picked Team_Calamity for team 1, adding 30.0 points for new total of 116.0",
             "Picked Team_Brute for team 1, adding 25.0 points for new total of 141.0",
             "Picked Team_Arbiter for team 2, adding 20.0 points for new total of 140.0"
           ]

    # Now 8 more users to test some 8v8 stuff
    %{user: u9} = ps9 = new_user("Team_Incisor") |> tachyon_auth_setup()
    %{user: u10} = ps10 = new_user("Team_Janus") |> tachyon_auth_setup()
    %{user: u11} = ps11 = new_user("Team_Karganeth") |> tachyon_auth_setup()
    %{user: u12} = ps12 = new_user("Team_Lancer") |> tachyon_auth_setup()
    %{user: u13} = ps13 = new_user("Team_Mace") |> tachyon_auth_setup()
    %{user: u14} = ps14 = new_user("Team_Nimrod") |> tachyon_auth_setup()
    %{user: u15} = ps15 = new_user("Team_Obscurer") |> tachyon_auth_setup()
    %{user: u16} = ps16 = new_user("Team_Pawn") |> tachyon_auth_setup()

    # Sleep to allow the users to be correctly added, otherwise we get PK errors we'd not
    # get in prod
    :timer.sleep(1000)

    [ps9, ps10, ps11, ps12, ps13, ps14, ps15, ps16]
    |> Enum.each(fn %{user: user, socket: socket} ->
      Lobby.force_add_user_to_lobby(user.id, lobby_id)
      # Need the sleep to ensure they all get added to the battle
      :timer.sleep(50)
      _tachyon_send(socket, %{cmd: "c.lobby.update_status", client: %{player: true, ready: true}})
    end)

    # Clear the old ratings so we can make some new ones
    old_ids = [u1, u2, u3, u4, u5, u6, u7, u8] |> Enum.map_join(",", fn u -> u.id end)
    query = "DELETE FROM teiserver_account_ratings WHERE user_id IN (#{old_ids})"
    query_result = Ecto.Adapters.SQL.query(Repo, query, [])

    assert elem(query_result, 0) == :ok,
      message: "The delete query failed so new ratings could not be created"

    # higher numbered players have higher ratings
    make_rating(u1.id, rating_type_id, 12)
    make_rating(u2.id, rating_type_id, 15)
    make_rating(u3.id, rating_type_id, 17)
    make_rating(u4.id, rating_type_id, 20)
    make_rating(u5.id, rating_type_id, 23)
    make_rating(u6.id, rating_type_id, 25)
    make_rating(u7.id, rating_type_id, 27)
    make_rating(u8.id, rating_type_id, 30)
    make_rating(u9.id, rating_type_id, 31)
    make_rating(u10.id, rating_type_id, 32)
    make_rating(u11.id, rating_type_id, 34)
    make_rating(u12.id, rating_type_id, 39)
    make_rating(u13.id, rating_type_id, 40)
    make_rating(u14.id, rating_type_id, 41)
    make_rating(u15.id, rating_type_id, 43)
    make_rating(u16.id, rating_type_id, 49)

    # Clear rating caches
    [u1, u2, u3, u4, u5, u6, u7, u8, u9, u10, u11, u12, u13, u14, u15, u16]
    |> Enum.each(fn %{id: userid} ->
      Teiserver.cache_delete(:teiserver_user_ratings, {userid, rating_type_id})
    end)

    # Leave the party
    Account.move_client_to_party(u8.id, nil)
    Account.move_client_to_party(u7.id, nil)
    Account.move_client_to_party(u6.id, nil)
    Account.move_client_to_party(u5.id, nil)

    :timer.sleep(50)

    # Assert we have no parties
    [u1, u2, u3, u4, u5, u6, u7, u8, u9, u10, u11, u12, u13, u14, u15, u16]
    |> Enum.each(fn %{id: userid} ->
      assert Account.get_client_by_id(userid).party_id == nil,
        message:
          "One or more of the users are currently in a party. At this stage of the test there should be no parties."
    end)

    # Get some new balance
    balance_result =
      Coordinator.call_balancer(lobby_id, {
        :make_balance,
        team_count,
        opts
      })

    assert Battle.get_lobby_balance_mode(lobby_id) == :grouped
    assert balance_result.balance_mode == :grouped

    assert Enum.sort(balance_result.team_players[1]) ==
             Enum.sort([
               u16.id,
               u13.id,
               u11.id,
               u10.id,
               u7.id,
               u6.id,
               u4.id,
               u1.id
             ])

    assert Enum.sort(balance_result.team_players[2]) ==
             Enum.sort([
               u15.id,
               u14.id,
               u12.id,
               u9.id,
               u8.id,
               u5.id,
               u3.id,
               u2.id
             ])

    assert balance_result.ratings == %{1 => 239.0, 2 => 239.0}
    assert balance_result.deviation == 0

    # Now test that fuzzing happens
    opts = [
      shuffle_first_pick: false,
      allow_groups: true,
      mean_diff_max: 20,
      stddev_diff_max: 10,
      rating_lower_boundary: 5,
      rating_upper_boundary: 5,
      max_deviation: 10,
      fuzz_multiplier: 0.5
    ]

    balance_result =
      Coordinator.call_balancer(lobby_id, {
        :make_balance,
        team_count,
        opts
      })

    assert Battle.get_lobby_balance_mode(lobby_id) == :grouped
    assert balance_result.balance_mode == :grouped
    refute balance_result.ratings == %{1 => 239.0, 2 => 239.0}

    :timer.sleep(3000)
  end

  test "server balance - ffa", %{
    lobby_id: lobby_id,
    host: _host,
    psocket: _psocket,
    player: player
  } do
    # We don't want to use the player we start with, we want to number our players specifically
    Lobby.remove_user_from_any_lobby(player.id)

    %{user: u1} = ps1 = new_user("FFA_Arbiter") |> tachyon_auth_setup()
    %{user: u2} = ps2 = new_user("FFA_Brute") |> tachyon_auth_setup()
    %{user: u3} = ps3 = new_user("FFA_Calamity") |> tachyon_auth_setup()

    rating_type_id = MatchRatingLib.rating_type_name_lookup()["FFA"]

    [ps1, ps2, ps3]
    |> Enum.each(fn %{user: user, socket: socket} ->
      Lobby.force_add_user_to_lobby(user.id, lobby_id)
      # Need the sleep to ensure they all get added to the battle
      :timer.sleep(50)
      _tachyon_send(socket, %{cmd: "c.lobby.update_status", client: %{player: true, ready: true}})
    end)

    # Create some ratings
    # higher numbered players have higher ratings
    make_rating(u1.id, rating_type_id, 20)
    make_rating(u2.id, rating_type_id, 25)
    make_rating(u3.id, rating_type_id, 30)

    # Wait for everybody to get added to the room
    :timer.sleep(250)

    consul_state = Coordinator.call_consul(lobby_id, :get_all)
    max_player_count = ConsulServer.get_max_player_count(consul_state)
    assert max_player_count >= 3

    assert Battle.list_lobby_players(lobby_id) |> Enum.count() == 3

    opts = [
      shuffle_first_pick: false,
      fuzz_multiplier: 0
    ]

    team_count = 3

    balance_result =
      Coordinator.call_balancer(lobby_id, {
        :make_balance,
        team_count,
        opts
      })

    assert balance_result.team_players[1] == [u3.id]
    assert balance_result.team_players[2] == [u2.id]
    assert balance_result.team_players[3] == [u1.id]
    assert balance_result.deviation == 17
    assert balance_result.ratings == %{1 => 30.0, 2 => 25.0, 3 => 20.0}
    assert Battle.get_lobby_balance_mode(lobby_id) == :solo

    # Ensure cache works
    assert Coordinator.call_balancer(lobby_id, {
             :make_balance,
             team_count,
             opts
           }) == balance_result

    # Ensure enabling groups won't break anything
    opts = [
      shuffle_first_pick: false,
      allow_groups: true,
      mean_diff_max: 15,
      stddev_diff_max: 10,
      rating_lower_boundary: 5,
      rating_upper_boundary: 5,
      max_deviation: 10,
      fuzz_multiplier: 0
    ]

    grouped_balance_result =
      Coordinator.call_balancer(lobby_id, {
        :make_balance,
        team_count,
        opts
      })

    assert Map.drop(grouped_balance_result, [:hash, :time_taken, :logs]) ==
             Map.drop(balance_result, [:hash, :time_taken, :logs])

    assert grouped_balance_result.hash != balance_result.hash

    :timer.sleep(3000)
  end

  test "server balance - team ffa", %{
    lobby_id: lobby_id,
    host: _host,
    psocket: _psocket,
    player: player
  } do
    # We don't want to use the player we start with, we want to number our players specifically
    Lobby.remove_user_from_any_lobby(player.id)

    %{user: u1} = ps1 = new_user("Team_FFA_Arbiter") |> tachyon_auth_setup()
    %{user: u2} = ps2 = new_user("Team_FFA_Brute") |> tachyon_auth_setup()
    %{user: u3} = ps3 = new_user("Team_FFA_Calamity") |> tachyon_auth_setup()
    %{user: u4} = ps4 = new_user("Team_FFA_Destroyer") |> tachyon_auth_setup()
    %{user: u5} = ps5 = new_user("Team_FFA_Eagle") |> tachyon_auth_setup()
    %{user: u6} = ps6 = new_user("Team_FFA_Fury") |> tachyon_auth_setup()
    %{user: u7} = ps7 = new_user("Team_FFA_Garpike") |> tachyon_auth_setup()
    %{user: u8} = ps8 = new_user("Team_FFA_Hound") |> tachyon_auth_setup()
    %{user: u9} = ps9 = new_user("Team_FFA_Incisor") |> tachyon_auth_setup()

    # Sleep to allow the users to be correctly added, otherwise we get PK errors we'd not
    # get in prod
    :timer.sleep(1000)

    rating_type_id = MatchRatingLib.rating_type_name_lookup()["Team"]

    [ps1, ps2, ps3, ps4, ps5, ps6, ps7, ps8, ps9]
    |> Enum.each(fn %{user: user, socket: socket} ->
      Lobby.force_add_user_to_lobby(user.id, lobby_id)
      # Need the sleep to ensure they all get added to the battle
      :timer.sleep(50)
      _tachyon_send(socket, %{cmd: "c.lobby.update_status", client: %{player: true, ready: true}})
    end)

    # Create some ratings
    # higher numbered players have higher ratings
    make_rating(u1.id, rating_type_id, 20)
    make_rating(u2.id, rating_type_id, 25)
    make_rating(u3.id, rating_type_id, 30)
    make_rating(u4.id, rating_type_id, 35)
    make_rating(u5.id, rating_type_id, 36)
    make_rating(u6.id, rating_type_id, 38)
    make_rating(u7.id, rating_type_id, 47)
    make_rating(u8.id, rating_type_id, 50)
    make_rating(u9.id, rating_type_id, 51)

    # Wait for everybody to get added to the room
    :timer.sleep(500)

    consul_state = Coordinator.call_consul(lobby_id, :get_all)
    max_player_count = ConsulServer.get_max_player_count(consul_state)
    assert max_player_count >= 9

    assert Battle.list_lobby_players(lobby_id) |> Enum.count() == 9

    opts = [
      shuffle_first_pick: false,
      fuzz_multiplier: 0
    ]

    team_count = 3

    balance_result =
      Coordinator.call_balancer(lobby_id, {
        :make_balance,
        team_count,
        opts
      })

    assert balance_result.team_players[1] == [u9.id, u4.id, u2.id]
    assert balance_result.team_players[2] == [u8.id, u5.id, u1.id]
    assert balance_result.team_players[3] == [u7.id, u6.id, u3.id]
    assert balance_result.deviation == 3
    assert balance_result.ratings == %{1 => 111, 2 => 106, 3 => 115}
    assert Battle.get_lobby_balance_mode(lobby_id) == :solo

    # Now do it grouped, these bounds mean it won't be able to find paired groups for
    # the party
    opts = [
      shuffle_first_pick: false,
      allow_groups: true,
      mean_diff_max: 15,
      stddev_diff_max: 10,
      rating_lower_boundary: 5,
      rating_upper_boundary: 5,
      max_deviation: 10,
      fuzz_multiplier: 0
    ]

    grouped_balance_result =
      Coordinator.call_balancer(lobby_id, {
        :make_balance,
        team_count,
        opts
      })

    assert Map.drop(grouped_balance_result, [:balance_mode, :hash, :time_taken, :logs]) ==
             Map.drop(balance_result, [:balance_mode, :hash, :time_taken, :logs])

    assert grouped_balance_result.hash != balance_result.hash

    # Party time, we start with the two highest rated players being put on the same team
    high_party = Account.create_party(u8.id)
    Account.move_client_to_party(u7.id, high_party.id)

    # Sleep so we don't get a cached list of players when calculating the balance
    :timer.sleep(520)

    party_balance_result =
      Coordinator.call_balancer(lobby_id, {
        :make_balance,
        team_count,
        opts
      })

    # Balance should be mostly the same
    assert Map.drop(grouped_balance_result, [:hash, :time_taken, :logs, :balance_mode]) ==
             Map.drop(balance_result, [:hash, :time_taken, :logs, :balance_mode])

    refute party_balance_result.hash == balance_result.hash

    # This time groups will work
    opts = [
      shuffle_first_pick: false,
      allow_groups: true,
      mean_diff_max: 150,
      stddev_diff_max: 100,
      rating_lower_boundary: 50,
      rating_upper_boundary: 50,
      max_deviation: 100,
      fuzz_multiplier: 0
    ]

    grouped_balance_result =
      Coordinator.call_balancer(lobby_id, {
        :make_balance,
        team_count,
        opts
      })

    assert grouped_balance_result.team_players[1] == [u7.id, u8.id, u1.id]
    assert grouped_balance_result.team_players[2] == [u6.id, u4.id, u5.id]
    assert grouped_balance_result.team_players[3] == [u3.id, u2.id, u9.id]
    assert grouped_balance_result.deviation == 7
    assert grouped_balance_result.ratings == %{1 => 117.0, 2 => 109.0, 3 => 106.0}
    assert Battle.get_lobby_balance_mode(lobby_id) == :grouped

    :timer.sleep(3000)
  end
end
