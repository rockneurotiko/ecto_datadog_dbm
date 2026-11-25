defmodule EctoDatadogDbm.Test.Repo do
  @moduledoc false
  use Ecto.Repo,
    otp_app: :ecto_datadog_dbm,
    adapter: Ecto.Adapters.Postgres
end

defmodule EctoDatadogDbm.Test.DisabledRepo do
  @moduledoc false
  use Ecto.Repo,
    otp_app: :ecto_datadog_dbm,
    adapter: Ecto.Adapters.Postgres
end

defmodule EctoDatadogDbm.Test.PlainRepo do
  @moduledoc false
  use Ecto.Repo,
    otp_app: :ecto_datadog_dbm,
    adapter: Ecto.Adapters.Postgres
end
