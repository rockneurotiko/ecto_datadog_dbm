defmodule EctoDatadogDbm.Pool do
  @moduledoc """
  Connection pool for the Repo `:pool` option.

  Delegates to `DBConnection.ConnectionPool`, swapping `Postgrex.Protocol` for
  `EctoDatadogDbm.Protocol`.
  """

  @behaviour DBConnection.Pool

  def child_spec({Postgrex.Protocol, opts}) do
    DBConnection.ConnectionPool.child_spec({EctoDatadogDbm.Protocol, opts})
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
