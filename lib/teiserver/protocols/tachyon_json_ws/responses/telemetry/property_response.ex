defmodule Teiserver.Tachyon.Responses.Telemetry.PropertyResponse do
  @moduledoc """

  """

  alias Teiserver.Data.Types, as: T

  @spec generate(atom) :: {T.tachyon_command(), T.tachyon_status(), T.tachyon_object()}
  def generate(:ok) do
    {"telemetry/property/response", :success, %{}}
  end
end
