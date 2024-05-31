defmodule Teiserver.Tachyon.Responses.Lobby.LeaveResponse do
  @moduledoc """

  """

  alias Teiserver.Data.Types, as: T

  @spec generate(:ok) :: T.tachyon_response()
  def generate(:ok) do
    {"lobby/leave/response", :success, %{}}
  end
end
