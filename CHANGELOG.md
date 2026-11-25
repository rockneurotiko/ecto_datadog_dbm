# Changelog

## Unreleased

- `EctoDatadogDbm.Pool`: a Repo `:pool` option that prefixes every statement Ecto sends
  to Postgres with a Datadog Database Monitoring comment. The adapter stays
  `Ecto.Adapters.Postgres`; telemetry, logs and `Postgrex.Error.query` keep the original SQL.
- Modes `:disabled`, `:service` (default) and `:full`, with `DD_DBM_PROPAGATION_MODE`,
  `DD_ENV`, `DD_SERVICE` and `DD_VERSION` as defaults that explicit options override.
- Statement policy `traceparent: :unnamed` (default), with opt-in `:sampled` and `:always`.
- `COMMIT` carries the static comment.
- Pluggable trace context (`EctoDatadogDbm.TraceContext`), OpenTelemetry by default
  with `opentelemetry_api` optional and `$callers` lookup for `Task` processes.
- Manual API: `EctoDatadogDbm.comment/2`, `inject/3`, `query/4` and `query!/4`.
- A contract test on the `DBConnection.ConnectionPool` surface used as a Repo pool.
- CI: format, credo, tests against Postgres, docs and `mix hex.audit`.
