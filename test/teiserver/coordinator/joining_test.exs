defmodule Teiserver.Coordinator.JoiningTest do
  use Teiserver.ServerCase, async: false
  alias Teiserver.Common.PubsubListener
  alias Teiserver.Account.ClientLib
  alias Teiserver.Coordinator

  alias Teiserver.Account.UserCacheLib

  import Teiserver.TeiserverTestLib,
    only: [tachyon_auth_setup: 0, _tachyon_send: 2, _tachyon_recv: 1]

  setup do
    Coordinator.start_coordinator()
    %{socket: socket, user: user} = tachyon_auth_setup()

    # User needs to be a moderator (at this time) to start/stop Coordinator mode
    UserCacheLib.update_user(%{user | moderator: true})
    ClientLib.refresh_client(user.id)

    battle_data = %{
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
        max_players: 12
      }
    }

    data = %{cmd: "c.lobby.create", lobby: battle_data}
    _tachyon_send(socket, data)
    [reply] = _tachyon_recv(socket)
    lobby_id = reply["lobby"]["id"]

    listener = PubsubListener.new_listener(["teiserver_lobby_chat:#{lobby_id}"])

    {:ok, socket: socket, user: user, lobby_id: lobby_id, listener: listener}
  end

  test "welcome message", %{socket: socket, user: user, lobby_id: lobby_id, listener: listener} do
    consul_state = Coordinator.call_consul(lobby_id, :get_all)
    assert consul_state.welcome_message == nil

    data = %{cmd: "c.lobby.message", message: "$welcome-message This is the welcome message"}
    _tachyon_send(socket, data)

    messages = PubsubListener.get(listener)

    assert messages == [
             %{
               channel: "teiserver_lobby_chat:#{lobby_id}",
               event: :announce,
               lobby_id: lobby_id,
               message: "New welcome message set to: This is the welcome message",
               userid: Coordinator.get_coordinator_userid()
             },
             %{
               channel: "teiserver_lobby_chat:#{lobby_id}",
               event: :say,
               lobby_id: lobby_id,
               message: "$welcome-message This is the welcome message",
               userid: user.id
             }
           ]

    consul_state = Coordinator.call_consul(lobby_id, :get_all)
    assert consul_state.welcome_message == "This is the welcome message"

    # Now a new user joins the battle
    %{socket: socket2, user: user2} = tachyon_auth_setup()
    data = %{cmd: "c.lobby.join", lobby_id: lobby_id}
    _tachyon_send(socket2, data)

    [reply] = _tachyon_recv(socket2)

    assert reply == %{
             "cmd" => "s.lobby.join",
             "result" => "waiting_for_host"
           }

    # Accept them
    data = %{cmd: "c.lobby_host.respond_to_join_request", userid: user2.id, response: "approve"}

    _tachyon_send(socket, data)
    [join_response] = _tachyon_recv(socket2)
    assert join_response["cmd"] == "s.lobby.joined"
    assert join_response["lobby"]["id"] == lobby_id

    # Expect welcome message
    [reply] = _tachyon_recv(socket2)

    assert reply == %{
             "cmd" => "s.communication.received_direct_message",
             "message" =>
               "########################################\nThis is the welcome message\n########################################",
             "sender_id" => Coordinator.get_coordinator_userid()
           }

    # Send the battle status
    data = %{
      cmd: "c.lobby.update_status",
      client: %{
        player: true,
        sync: 1,
        player_number: 0,
        team_number: 0,
        side: 0,
        team_colour: "0",
        ready: true
      }
    }

    _tachyon_send(socket2, data)

    # We expect to hear about our new status
    [reply] = _tachyon_recv(socket2)

    assert reply == %{
             "cmd" => "s.lobby.updated_client_battlestatus",
             "client" => %{
               "team_number" => 0,
               "away" => false,
               "in_game" => false,
               "lobby_id" => lobby_id,
               "ready" => false,
               "team_colour" => "0",
               "player_number" => 0,
               "userid" => user2.id,
               "player" => true,
               "sync" => ["game", "map"],
               "clan_tag" => nil,
               "muted" => false,
               "party_id" => nil
             },
             "lobby_id" => lobby_id,
             "reason" => "client_updated_battlestatus"
           }

    # No more messages
    reply = _tachyon_recv(socket2)
    assert reply == :timeout
  end
end
