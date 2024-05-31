defmodule Teiserver.Tachyon.Handlers.Lobby.ListLobbiesRequest do
  @moduledoc """

  """
  alias Teiserver.Data.Types, as: T
  alias Teiserver.Tachyon.Converters
  alias Teiserver.Battle
  alias Teiserver.Tachyon.Responses.Lobby.ListLobbiesResponse

  @spec dispatch_handlers :: map()
  def dispatch_handlers() do
    %{
      "lobby/list_lobbies/request" => &execute/3
    }
  end

  @spec execute(T.tachyon_conn(), T.tachyon_object(), map) ::
          {T.tachyon_response(), T.tachyon_conn()}
  def execute(conn, _object, _meta) do
    lobbies =
      Battle.list_lobbies()
      |> Converters.convert(:lobby)

    response = ListLobbiesResponse.generate(lobbies)

    {response, conn}
  end
end
