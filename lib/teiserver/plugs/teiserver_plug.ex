defmodule Teiserver.ServerUserPlug do
  import Plug.Conn
  alias Teiserver.CacheUser

  def init(_opts) do
    # Keyword.fetch!(opts, :repo)
  end

  @spec call(Plug.Conn.t(), any) :: Plug.Conn.t()
  def call(%{assigns: %{current_user: nil}} = conn, _opts) do
    conn
    |> assign(:server_user, nil)
  end

  def call(%{assigns: %{current_user: current_user}} = conn, _opts) do
    userid = current_user.id
    server_user = CacheUser.get_user_by_id(userid)

    conn
    |> assign(:server_user, server_user)
  end

  def call(conn, _opts) do
    conn
    |> assign(:server_user, nil)
  end

  def live_call(%{assigns: %{current_user: nil}} = socket) do
    socket
  end

  def live_call(%{assigns: %{current_user: current_user}} = socket) do
    userid = current_user.id
    server_user = CacheUser.get_user_by_id(userid)

    socket
    |> Phoenix.LiveView.Utils.assign(:server_user, server_user)
  end
end
