defmodule EctoDatadogDbm.Test.Repo do
  @moduledoc false
  use Ecto.Repo,
    otp_app: :ecto_datadog_dbm,
    adapter: Ecto.Adapters.Postgres
end
