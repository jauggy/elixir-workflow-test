defmodule Teiserver.Logging.AuditLog do
  @moduledoc false
  use TeiserverWeb, :schema

  schema "audit_logs" do
    field :action, :string
    field :details, :map
    field :ip, :string

    belongs_to :user, Teiserver.Account.User

    timestamps()
  end

  @doc false
  def changeset(struct, params) do
    struct
    |> cast(params, ~w(action details ip user_id)a)
    |> validate_required(~w(action details)a)
  end

  @spec authorize(any, Plug.Conn.t(), atom) :: boolean
  def authorize(_, conn, :delete), do: allow?(conn, "logging.audit.delete")
  def authorize(_, conn, _), do: allow?(conn, "logging.audit")
end
