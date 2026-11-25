defmodule EctoDatadogDbm.Pool do
  @moduledoc """
  Connection pool for the Repo `:pool` option.

  Delegates to `DBConnection.ConnectionPool`, swapping the Postgrex protocol module for
  `EctoDatadogDbm.Protocol`.
  """

  @behaviour DBConnection.Pool

  alias EctoDatadogDbm.{Comment, Config}

  def child_spec({Postgrex.Protocol, %DBConnection.SensitiveData{data: opts}}) do
    child_spec({Postgrex.Protocol, opts})
  end

  def child_spec({Postgrex.Protocol, opts}) do
    dbm = Keyword.get(opts, :dbm) || raise ArgumentError, "the :dbm configuration is required"
    config = Config.new!(dbm)
    opts = Keyword.merge(opts, dbm: config, dbm_comment: Comment.build(config))

    DBConnection.ConnectionPool.child_spec(
      {EctoDatadogDbm.Protocol, %DBConnection.SensitiveData{data: opts}}
    )
  end

  def child_spec({module, _opts}) do
    raise ArgumentError,
          "EctoDatadogDbm.Pool only supports Postgrex.Protocol, got: #{inspect(module)}"
  end

  @impl true
  defdelegate checkout(pool, callers, opts), to: DBConnection.ConnectionPool

  @impl true
  defdelegate disconnect_all(pool, interval, opts), to: DBConnection.ConnectionPool

  @impl true
  defdelegate get_connection_metrics(pool), to: DBConnection.ConnectionPool
end
