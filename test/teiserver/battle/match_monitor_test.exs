defmodule Teiserver.Battle.MatchMonitorTest do
  use Teiserver.ServerCase, async: false

  import Teiserver.TeiserverTestLib,
    only: [
      auth_setup: 0,
      _send_raw: 2,
      _recv_raw: 1,
      _recv_until: 1
    ]

  setup do
    Teiserver.Battle.start_match_monitor()
    {:ok, %{}}
  end

  # This test is to ensure long messages are not being truncated
  test "spring send" do
    %{socket: socket, user: _user} = auth_setup()

    # monitor_userid = Teiserver.cache_get(:application_metadata_cache, "teiserver_match_monitor_userid")

    # Send a direct message to the match monitor server
    short_data =
      %{key: "value"}
      |> Jason.encode!()
      |> Base.url_encode64()

    _send_raw(socket, "SAYPRIVATE AutohostMonitor endGameData #{short_data}\n")
    result = _recv_raw(socket)
    assert result == "SAYPRIVATE AutohostMonitor endGameData eyJrZXkiOiJ2YWx1ZSJ9\n"

    # Now try longer data
    long_start = %{key: "This is a very long string"}

    long_data =
      0..60
      |> Enum.reduce(long_start, fn _, acc ->
        Map.put(acc, :sub, acc)
      end)
      |> Jason.encode!()
      |> Base.url_encode64()

    _send_raw(socket, "SAYPRIVATE AutohostMonitor endGameData #{long_data}\n")
    result = _recv_until(socket)

    assert result =~
             "SAYPRIVATE AutohostMonitor endGameData eyJrZXkiOiJUaGlzIGlzIGEgdmVyeSBsb25nIHN0cmluZyIsInN1YiI6eyJrZXkiOiJ"

    assert result =~ "X19fX19fX19fX19fX19fX19fQ==\n"
    assert String.length(result) == 3588
  end
end
