defmodule EctoDatadogDbm.PrefixTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias EctoDatadogDbm.Test.Repo

  @prefix "/*dddbs='test-db',dde='test',ddps='test-app',ddpv='1.0.0'*/ SELECT"

  defp current_query, do: from(c in "pg_class", select: fragment("current_query()"), limit: 1)

  test "the server sees the prefix on first and cached named runs" do
    Repo.checkout(fn ->
      assert [@prefix <> _] = Repo.all(current_query())
      assert [@prefix <> _] = Repo.all(current_query())

      assert %{rows: [[1]]} =
               Repo.query!(
                 "SELECT count(*)::int FROM pg_prepared_statements WHERE statement LIKE '/*dddbs%'"
               )
    end)
  end

  test "telemetry reports the original SQL" do
    ref = make_ref()
    parent = self()

    :telemetry.attach(
      ref,
      [:ecto_datadog_dbm, :test, :repo, :query],
      fn _, _, meta, _ -> send(parent, {:query, meta.query}) end,
      nil
    )

    Repo.all(current_query())
    :telemetry.detach(ref)

    assert_received {:query, "SELECT current_query() FROM \"pg_class\" AS p0 LIMIT 1"}
  end

  test "errors carry the original statement" do
    assert {:error, %Postgrex.Error{query: "SELEC 1"}} = Repo.query("SELEC 1")
  end

  test "the adapter is unchanged" do
    assert Repo.__adapter__() == Ecto.Adapters.Postgres
  end
end
