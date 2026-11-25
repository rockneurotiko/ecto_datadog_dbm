import Config

url =
  System.get_env(
    "ECTO_DATADOG_DBM_TEST_DATABASE_URL",
    "postgres://postgres:postgres@localhost/ecto_datadog_dbm_test"
  )

config :ecto_datadog_dbm, EctoDatadogDbm.Test.PlainRepo, url: url, pool_size: 2

config :ecto_datadog_dbm, EctoDatadogDbm.Test.DisabledRepo,
  url: url,
  pool: EctoDatadogDbm.Pool,
  pool_size: 2,
  dbm: [mode: :disabled]

config :ecto_datadog_dbm, EctoDatadogDbm.Test.Repo,
  url: url,
  pool: EctoDatadogDbm.Pool,
  pool_size: 2,
  dbm: [
    mode: :full,
    dddbs: "test-db",
    dde: "test",
    ddps: "test-app",
    ddpv: "1.0.0"
  ]

for {repo, policy} <- [SampledRepo: :sampled, AlwaysRepo: :always] do
  config :ecto_datadog_dbm, Module.concat(EctoDatadogDbm.Test, repo),
    url: url,
    pool: EctoDatadogDbm.Pool,
    pool_size: 1,
    dbm: [
      mode: :full,
      dddbs: "test-db",
      dde: "test",
      ddps: "test-app",
      ddpv: "1.0.0",
      traceparent: policy
    ]
end

config :opentelemetry, traces_exporter: :none, processors: []
config :logger, level: :warning
