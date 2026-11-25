import Config

config :ecto_datadog_dbm, EctoDatadogDbm.Test.Repo,
  url:
    System.get_env(
      "ECTO_DATADOG_DBM_TEST_DATABASE_URL",
      "postgres://postgres:postgres@localhost/ecto_datadog_dbm_test"
    ),
  pool: EctoDatadogDbm.Pool,
  pool_size: 2,
  dbm: [
    dddbs: "test-db",
    dde: "test",
    ddps: "test-app",
    ddpv: "1.0.0"
  ]
