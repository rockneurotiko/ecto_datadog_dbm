# EctoDatadogDbm

Links Datadog Database Monitoring (DBM) query samples to APM traces for Ecto and Postgres.

Every SQL statement Ecto sends carries a leading comment with service tags and, when
useful, a W3C `traceparent`:

```sql
/*dddb='app_prod',dddbs='my-service-db',dde='prod',ddps='my-service',ddpv='1.2.0'*/ SELECT ...
```

DBM uses it to jump from a query sample to the trace that issued it, and back. The
comment is added by a `DBConnection` wrapper around Postgrex.Protocol, enabled
through the Repo `:pool` option. The adapter stays `Ecto.Adapters.Postgres`, so Oban,
`opentelemetry_ecto`, dev loggers and Ecto telemetry keep working and keep seeing the
original SQL. Postgres only.

## Quick start

```elixir
# mix.exs
{:ecto_datadog_dbm, "~> 0.1"},
{:opentelemetry_api, "~> 1.4"},  # optional, for traceparent
{:opentelemetry_process_propagator, "~> 0.3"}  # optional, only for Task callers

# config/runtime.exs
config :my_app, MyApp.Repo,
  pool: EctoDatadogDbm.Pool,
  dbm: [
    mode: :full,
    dddbs: "my-service-db",
    dde: "prod",
    ddps: "my-service",
    ddpv: "1.2.0"
  ]
```

`dddbs` is required (except in `:disabled` mode) and has no default; a missing one
raises `ArgumentError` when the Repo starts. Invalid options raise too.

Options: `mode`, `dddbs`, `dde`, `ddps`, `ddpv`, `ddh` (db host, unset by default),
`dddb` (db name), `trace_context` (a module implementing `EctoDatadogDbm.TraceContext`,
default `EctoDatadogDbm.TraceContext.OpenTelemetry`) and `traceparent` (statement policy).
Keys with `nil` or empty values are left out; values are percent-encoded, so nothing
can break out of the comment.

## Modes

| Mode        | Comment                                              |
| ----------- | ---------------------------------------------------- |
| `:disabled` | nothing; statements are byte-identical to no wrapper |
| `:service`  | static service tags (default)                        |
| `:full`     | service tags plus `traceparent` where allowed        |

Unset options fall back to the environment: `DD_DBM_PROPAGATION_MODE`
(`disabled`/`service`/`full`), `DD_ENV` (`dde`), `DD_SERVICE` (`ddps`) and
`DD_VERSION` (`ddpv`). Explicit options win. With neither, the mode is `:service`.

In `:full` mode the `traceparent` is `00-<trace id>-<span id>-<01|00>` (`01` when the
trace is sampled). With no active span, invalid ids, or `opentelemetry_api` absent, the
comment is service-only. `Task` processes use their caller's span through
`$callers` when `opentelemetry_process_propagator` is installed.

## Manual usage

For SQL that does not go through the pool:

```elixir
config = [mode: :full, dddbs: "db"]

EctoDatadogDbm.comment(config, :current)
#=> "/*dddbs='db',traceparent='00-...-...-01'*/"
# DD_ENV / DD_SERVICE / DD_VERSION add dde / ddps / ddpv when set.

EctoDatadogDbm.inject("SELECT 1", config, :current)  # iodata with the comment prepended

EctoDatadogDbm.query(MyApp.Repo, "SELECT $1::int", [1])
EctoDatadogDbm.query!(MyApp.Repo, "SELECT $1::int", [1])
```

The second argument of `comment/2` and `inject/3` is a trace context map
(`%{trace_id:, span_id:, sampled?:}`), `nil`, or `:current` for the configured
trace-context module. `query/4` and `query!/4` wrap `Repo.query` and force an unnamed
statement so the traceparent is fresh. A Repo using `EctoDatadogDbm.Pool` comments the
statement itself; any other Repo gets the comment prepended from the `:dbm` option or
Repo config. The pool is detected from the Repo's static config (`repo.config/0`), so
dynamic repos and wrapper pools are not recognised and would be commented twice.

## Statement policy

Postgres named prepared statements send their text once, at Parse, so a per-query
traceparent in a named statement would go stale. Unnamed statements are re-parsed on
every call. The `traceparent` option picks the trade-off:

- `:unnamed` (default): named statements get the static service comment only, which
  never changes and so keeps the statement cache valid. Unnamed statements
  (`Repo.query`, `prepare: :unnamed`, `query_cache: false`, text queries) also get the
  `traceparent` in `:full` mode.
- `:sampled`: a statement in a sampled trace runs once as an unnamed statement with the
  full comment; the cached named statement is not replaced. Unsampled runs stay named
  with the static comment. It only saves work if sampling is below 100%.
- `:always`: every statement runs unnamed with the `traceparent`.

Measured on loopback:

| Case                                          | µs/op |
| --------------------------------------------- | ----: |
| named, no wrapper                             |  39.7 |
| named, static prefix                          |  43.6 |
| unnamed, changing prefix                      |  63.0 |
| 6-join query, unnamed (re-planned every time) | 132.2 |
| 6-join query, named                           |  36.7 |

`insert`/`update`/`delete` use Postgrex's statement cache: a changing comment makes
each call Close + Parse, while a static one stays cached. Over a real network the
unnamed cost is higher than on loopback. A differing leading comment does not change
the `pg_stat_statements` `queryid`.

## Datadog setup

- `dddbs` must equal the service name of the database spans in Datadog, or DBM and APM
  will not match. Use the same `DD_*` environment as the rest of the service.
- Postgres truncates `pg_stat_activity.query` at `track_activity_query_size` (default
  1024 bytes). A prefix survives truncation, a suffix is lost on long queries, which is
  why this library prefixes. Setting it to `4096` is recommended.
- Set up Database Monitoring for the Postgres host as described in the Datadog docs
  (including `dbm: true` on the Agent's Postgres instance). The Agent reads the SQL
  comment from the statements it samples; there is no separate option for comments.
- DBM links a query sample to the APM trace through the `traceparent` in the SQL
  comment. A prefix and a suffix comment are both accepted, but only the prefix
  survives truncation at `track_activity_query_size`. Real SQL in the APM
  `db.statement` without the comment does not correlate. This was observed on a
  DBM-enabled Postgres 18 host with the Datadog Agent; how the Datadog UI renders the
  link was not exercised.
- `opentelemetry_api` is optional; without it comments are service-only. Task support
  needs `opentelemetry_process_propagator`.

## Multiple Repos and replicas

Share one keyword list so a primary and its replica are tagged alike:

```elixir
dbm = [mode: :full, dddbs: "my-service-db", dde: "prod", ddps: "my-service"]

config :my_app, MyApp.Repo, pool: EctoDatadogDbm.Pool, dbm: dbm
config :my_app, MyApp.ReplicaRepo, pool: EctoDatadogDbm.Pool, dbm: dbm
```

## Limitations

- `BEGIN` and `ROLLBACK` are not commented (Postgrex has no hook); `COMMIT` carries the
  static comment.
- Ecto SQL Sandbox forces `DBConnection.Ownership`, which makes the wrapper a no-op, so
  tests using the sandbox see no comments. Test this library's behaviour against a real
  non-sandbox Repo.
- Connection error logs name `EctoDatadogDbm.Protocol` instead of Postgrex.Protocol.
- The span id in the `traceparent` is the current (parent) span, because the database
  span does not exist yet when the comment is built.
- `:sampled`/`:always`: (1) a freshly prepared named statement that Postgrex has not yet
  synced keeps the named statement with the static comment for its first execution;
  (2) under `:always` Ecto's prepare still creates the named statement once per
  statement and connection.
- `:sampled`/`:always` rely on Postgrex internal connection state, verified on
  Postgrex 0.23.0. Pin Postgrex and run your tests on upgrades.
- Only Postgrex.Protocol is supported; other drivers raise `ArgumentError`.
- Manual `query/4` pool detection reads the Repo's static config.

## License

MIT
