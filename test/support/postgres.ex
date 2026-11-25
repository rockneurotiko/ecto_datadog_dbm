defmodule EctoDatadogDbm.Test.Postgres do
  @moduledoc false

  alias Ecto.Adapters.Postgres
  alias EctoDatadogDbm.Test.Repo

  @doc "Creates the test database when missing and starts the non-sandbox Repo."
  def start! do
    case Postgres.storage_up(Repo.config()) do
      :ok -> :ok
      {:error, :already_up} -> :ok
      {:error, reason} -> raise "cannot create test database: #{inspect(reason)}"
    end

    {:ok, _} = Repo.start_link()
    :ok
  end
end
