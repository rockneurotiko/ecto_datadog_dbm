defmodule EctoDatadogDbm.Test.Postgres do
  @moduledoc false

  alias Ecto.Adapters.Postgres
  alias EctoDatadogDbm.Test.{AlwaysRepo, DisabledRepo, PlainRepo, Repo, SampledRepo}

  @doc "Creates the test database when missing and starts the non-sandbox Repo."
  def start! do
    case Postgres.storage_up(Repo.config()) do
      :ok -> :ok
      {:error, :already_up} -> :ok
      {:error, reason} -> raise "cannot create test database: #{inspect(reason)}"
    end

    for repo <- [Repo, DisabledRepo, PlainRepo, SampledRepo, AlwaysRepo],
        do: {:ok, _} = repo.start_link()

    :ok
  end
end
