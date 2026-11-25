defmodule EctoDatadogDbm.PolicyTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  require OpenTelemetry.Tracer, as: Tracer

  alias EctoDatadogDbm.Test.{AlwaysRepo, Env, SampledRepo}

  @static "/*dddbs='test-db',dde='test',ddps='test-app',ddpv='1.0.0'*/ SELECT"

  setup do
    Env.clear!()
    on_exit(fn -> Tracer.set_current_span(:undefined) end)
  end

  defp current_query, do: from(c in "pg_class", select: fragment("current_query()"), limit: 1)

  # Parameterised so Ecto prepares a named statement for it.
  defp text(repo), do: repo.one(current_query())

  defp prepared(repo) do
    repo.query!(
      "SELECT name, prepare_time FROM pg_prepared_statements WHERE statement LIKE '%current_query()%pg_class%'"
    ).rows
  end

  defp unsampled, do: Tracer.set_current_span(:otel_tracer.from_remote_span(1, 2, 0))

  describe ":sampled" do
    test "a sampled run is unnamed with traceparent and leaves the named statement untouched" do
      assert text(SampledRepo) =~ @static
      assert [[name, prepared_at]] = prepared(SampledRepo)
      assert name != ""

      sampled = Tracer.with_span("work", do: text(SampledRepo))
      assert sampled =~ ~r/traceparent='00-[0-9a-f]{32}-[0-9a-f]{16}-01'.*\*\/ SELECT/

      assert [[^name, ^prepared_at]] = prepared(SampledRepo)
    end

    test "an unsampled span keeps the named statement and the static comment" do
      unsampled()
      assert text(SampledRepo) =~ @static
      refute text(SampledRepo) =~ "traceparent"
    end

    test "the Ecto cache stays valid after a sampled run" do
      assert text(SampledRepo) =~ @static
      [[name, prepared_at]] = prepared(SampledRepo)

      Tracer.with_span("work", do: text(SampledRepo))
      after_run = text(SampledRepo)

      assert after_run =~ @static
      refute after_run =~ "traceparent"
      assert [[^name, ^prepared_at]] = prepared(SampledRepo)
    end

    test "a failing sampled statement reports the original SQL" do
      Tracer.with_span "work" do
        assert {:error, %Postgrex.Error{query: "SELECT nope FROM nowhere"}} =
                 SampledRepo.query("SELECT nope FROM nowhere", [], prepare: :named)
      end
    end

    test "writes and transactions keep working in a sampled span" do
      # insert_all prepares a statement that locks the connection until it is executed,
      # so the first run cannot be sent as an unnamed copy; a second run must still work.
      Tracer.with_span "work" do
        assert {:ok, 1} =
                 SampledRepo.transaction(fn ->
                   SampledRepo.query!("CREATE TEMP TABLE IF NOT EXISTS t (a int)")
                   SampledRepo.insert_all("t", [%{a: 1}]) |> elem(0)
                 end)

        assert {:ok, 1} =
                 SampledRepo.transaction(fn ->
                   SampledRepo.insert_all("t", [%{a: 2}]) |> elem(0)
                 end)

        assert SampledRepo.all(from(t in "t", select: t.a, order_by: t.a)) == [1, 2]
      end
    end

    test "streams keep working in a sampled span" do
      Tracer.with_span "work" do
        assert {:ok, rows} =
                 SampledRepo.transaction(fn ->
                   from(g in fragment("generate_series(1, 3)"),
                     select: {fragment("?", g), fragment("current_query()")}
                   )
                   |> SampledRepo.stream(max_rows: 1)
                   |> Enum.to_list()
                 end)

        assert [1, 2, 3] = Enum.map(rows, &elem(&1, 0))
        assert Enum.all?(rows, fn {_, sql} -> sql =~ "traceparent=" end)
      end
    end
  end

  describe ":always" do
    test "every execution carries traceparent, whatever the sampling flag" do
      Tracer.with_span "work" do
        for _ <- 1..2, do: assert(text(AlwaysRepo) =~ ~r/traceparent='00-[0-9a-f]{32}-/)
      end

      unsampled()
      assert text(AlwaysRepo) =~ "-00'"
    end

    test "without a span the static comment is used and nothing fails" do
      assert text(AlwaysRepo) =~ @static
      refute text(AlwaysRepo) =~ "traceparent"
    end

    test "the traceparent differs between spans" do
      a = Tracer.with_span("a", do: text(AlwaysRepo))
      b = Tracer.with_span("b", do: text(AlwaysRepo))
      refute a == b
    end
  end

  for {repo, policy} <- [{SampledRepo, ":sampled"}, {AlwaysRepo, ":always"}] do
    describe "#{policy} statements that lock the connection or fail" do
      test "a cold statement inside a transaction runs with the static comment" do
        repo = unquote(repo)
        table = "cold_#{System.unique_integer([:positive])}"

        Tracer.with_span "work" do
          assert {:ok, 1} =
                   repo.transaction(fn ->
                     repo.query!("CREATE TEMP TABLE #{table} (a int)")
                     {1, _} = repo.insert_all(table, [%{a: 1}])
                     1
                   end)

          assert repo.all(from(t in table, select: t.a)) == [1]
          assert text(repo) =~ "traceparent="
        end
      end

      test "an execute-time error keeps its shape and leaves the connection usable" do
        repo = unquote(repo)
        table = "uniq_#{System.unique_integer([:positive])}"
        sql = "INSERT INTO #{table} (a) VALUES ($1)"

        repo.query!("CREATE TEMP TABLE #{table} (a int PRIMARY KEY)")

        repo.checkout(fn ->
          repo.query!(sql, [1], prepare: :named)

          plain = repo.query(sql, [1], prepare: :named)
          traced = Tracer.with_span("work", do: repo.query(sql, [1], prepare: :named))

          assert {:error, %Postgrex.Error{postgres: %{code: :unique_violation}}} =
                   traced

          assert traced == plain

          assert_raise Postgrex.Error, ~r/unique/, fn ->
            Tracer.with_span("work", do: repo.insert_all(table, [%{a: 1}]))
          end

          assert {:ok, %{rows: [[1]]}} = repo.query("SELECT 1")
        end)
      end
    end
  end
end
