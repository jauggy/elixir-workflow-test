defmodule Teiserver.Throttles do
  @spec start_throttle(integer(), module(), String.t()) :: pid()
  def start_throttle(id, module, name) do
    {:ok, throttle_pid} =
      DynamicSupervisor.start_child(Teiserver.Throttles.Supervisor, {
        module,
        name: name, data: %{id: id}
      })

    throttle_pid
  end

  @spec get_throttle_pid({atom(), integer()}) :: pid() | nil
  def get_throttle_pid(key) do
    case Horde.Registry.lookup(Teiserver.ThrottleRegistry, key) do
      [{pid, _}] ->
        pid

      _ ->
        nil
    end
  end

  @spec stop_throttle({atom(), integer()}) :: nil | :ok
  def stop_throttle(key) do
    case get_throttle_pid(key) do
      nil ->
        nil

      pid ->
        DynamicSupervisor.terminate_child(Teiserver.Throttles.Supervisor, pid)
        :ok
    end
  end
end
