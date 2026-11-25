defmodule EctoDatadogDbm do
  @moduledoc """
  Datadog Database Monitoring comments for Ecto.

  Enable the comment for every statement of a Repo with `pool: EctoDatadogDbm.Pool`
  and a `:dbm` option. The functions here build or inject the same comment for SQL
  that bypasses the pool.

  A manual statement is always unnamed, so in `:full` mode its comment carries a
  `traceparent` whenever a trace context is available.
  """

  alias EctoDatadogDbm.{Comment, Config}

  @type config :: Config.t() | keyword()
  @type ctx :: EctoDatadogDbm.TraceContext.ctx() | nil | :current

  @doc """
  Builds the comment text for an unnamed statement, or `""` when there is nothing to inject.

  `ctx` is a trace context, `nil` for none, or `:current` to ask the config's
  `:trace_context` module for the caller's context. A keyword config goes through
  `EctoDatadogDbm.Config.new!/1`.

  ## Examples

      iex> EctoDatadogDbm.comment([mode: :service, dddbs: "db", dde: "prod"], nil)
      "/*dddbs='db',dde='prod'*/"

      iex> ctx = %{trace_id: String.duplicate("a", 32), span_id: String.duplicate("b", 16), sampled?: true}
      iex> EctoDatadogDbm.comment([mode: :full, dddbs: "db"], ctx)
      "/*dddbs='db',traceparent='00-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-bbbbbbbbbbbbbbbb-01'*/"

  """
  @spec comment(config(), ctx()) :: String.t()
  def comment(config, ctx) do
    config = to_config(config)
    Comment.build(config, resolve(ctx, config), named?: false)
  end

  @doc """
  Prepends the comment to a statement. Arguments are as for `comment/2`.

  Valid iodata (binaries, iolists, charlists) is commented. `nil`, `""`, `[]` and
  anything that is not iodata are returned unchanged.

  ## Examples

      iex> statement = EctoDatadogDbm.inject("SELECT 1", [mode: :service, dddbs: "db"], nil)
      iex> IO.iodata_to_binary(statement)
      "/*dddbs='db'*/ SELECT 1"

      iex> EctoDatadogDbm.inject(nil, [mode: :service, dddbs: "db"], nil)
      nil

  """
  @spec inject(iodata(), config(), ctx()) :: iodata()
  def inject(statement, config, ctx), do: Comment.prefix(statement, comment(config, ctx))

  @doc """
  Like `Repo.query/4`, but the statement is unnamed, so its traceparent is fresh.

  The comment comes from the `:dbm` option, else from the Repo's `:dbm` config. A Repo
  using `EctoDatadogDbm.Pool` comments the statement itself, so it is only forced
  unnamed here; any other Repo gets the comment prepended here, and an explicit `:dbm`
  option is ignored for a pooled Repo. A non-pooled Repo needs a `:dbm` option or config
  that yields a `:dddbs` (or env default), else `ArgumentError` is raised.

  The pool check reads the Repo's static config (`repo.config/0`), so dynamic repos and
  wrapper pools are not detected: such a statement would be commented twice. Don't mix
  them with this function, or use a plain Repo.
  """
  @spec query(Ecto.Repo.t() | module(), iodata(), list(), keyword()) ::
          {:ok, Postgrex.Result.t()} | {:error, Exception.t()}
  def query(repo, statement, params \\ [], opts \\ []) do
    {statement, opts} = prepare(repo, statement, opts)
    repo.query(statement, params, opts)
  end

  @doc "Like `query/4`, raising on error."
  @spec query!(Ecto.Repo.t() | module(), iodata(), list(), keyword()) :: Postgrex.Result.t()
  def query!(repo, statement, params \\ [], opts \\ []) do
    {statement, opts} = prepare(repo, statement, opts)
    repo.query!(statement, params, opts)
  end

  defp prepare(repo, statement, opts) do
    {dbm, opts} = Keyword.pop(opts, :dbm)
    repo_config = repo.config()
    opts = Keyword.put(opts, :prepare, :unnamed)

    if repo_config[:pool] == EctoDatadogDbm.Pool do
      {statement, opts}
    else
      {inject(statement, dbm || repo_config[:dbm] || [], :current), opts}
    end
  end

  defp to_config(%Config{} = config), do: config
  defp to_config(opts) when is_list(opts), do: Config.new!(opts)

  defp resolve(:current, %Config{trace_context: module}) do
    case module.current() do
      {:ok, ctx} -> ctx
      :none -> nil
    end
  end

  defp resolve(ctx, _config), do: ctx
end
