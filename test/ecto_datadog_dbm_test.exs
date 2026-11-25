defmodule EctoDatadogDbmTest do
  use ExUnit.Case, async: false
  doctest EctoDatadogDbm

  require OpenTelemetry.Tracer, as: Tracer

  alias EctoDatadogDbm.Config
  alias EctoDatadogDbm.Test.{Env, PlainRepo, Repo}

  @ctx %{trace_id: String.duplicate("a", 32), span_id: String.duplicate("b", 16), sampled?: true}
  @opts [mode: :full, dddbs: "svc", dde: "test"]
  @traceparent "traceparent='00-#{@ctx.trace_id}-#{@ctx.span_id}-01'"

  setup do
    Env.clear!()
    on_exit(fn -> Tracer.set_current_span(:undefined) end)
  end

  defp text(result), do: result.rows |> hd() |> hd()

  describe "comment/2" do
    test "accepts a keyword or a struct" do
      expected = "/*dddbs='svc',dde='test',#{@traceparent}*/"

      assert EctoDatadogDbm.comment(@opts, @ctx) == expected
      assert EctoDatadogDbm.comment(Config.new!(@opts), @ctx) == expected
    end

    test "has no traceparent without a context or outside :full mode" do
      assert EctoDatadogDbm.comment(@opts, nil) == "/*dddbs='svc',dde='test'*/"
      assert EctoDatadogDbm.comment([mode: :service, dddbs: "svc"], @ctx) == "/*dddbs='svc'*/"
      assert EctoDatadogDbm.comment([mode: :disabled], @ctx) == ""
    end

    test ":current reads the active span" do
      Tracer.with_span "work" do
        assert EctoDatadogDbm.comment(@opts, :current) =~ ~r/traceparent='00-[0-9a-f]{32}-/
      end

      assert EctoDatadogDbm.comment(@opts, :current) == "/*dddbs='svc',dde='test'*/"
    end

    test "a keyword config takes env defaults" do
      System.put_env("DD_ENV", "from-env")
      assert EctoDatadogDbm.comment([mode: :service, dddbs: "svc"], nil) =~ "dde='from-env'"
    end
  end

  describe "inject/3" do
    test "prepends the comment to binary and iodata statements" do
      comment = EctoDatadogDbm.comment(@opts, @ctx)

      statement = EctoDatadogDbm.inject("SELECT 1", @opts, @ctx)
      assert IO.iodata_to_binary(statement) == comment <> " SELECT 1"

      for input <- [["SELECT ", ["1"]], ~c"SELECT 1", ["SE", [~c"LECT", [" 1"]]]] do
        statement = EctoDatadogDbm.inject(input, Config.new!(@opts), @ctx)
        assert IO.iodata_to_binary(statement) == comment <> " SELECT 1"
      end
    end

    test "passes non-iodata through unchanged without raising" do
      for input <- [:select, 1, ["SELECT " | :a], [1.5], %{}, {"SELECT"}, [[] | :a]] do
        assert EctoDatadogDbm.inject(input, @opts, @ctx) == input
      end
    end

    test "passes nil and empty statements through" do
      for statement <- [nil, "", []] do
        assert EctoDatadogDbm.inject(statement, @opts, @ctx) == statement
      end
    end

    test "leaves the statement alone when disabled" do
      assert EctoDatadogDbm.inject("SELECT 1", [mode: :disabled], @ctx) == "SELECT 1"
    end
  end

  describe "query/4 and query!/4 on a Repo without the pool" do
    test "carry a fresh traceparent per span" do
      for run <- [
            fn -> EctoDatadogDbm.query!(PlainRepo, "SELECT current_query()") end,
            fn ->
              {:ok, result} = EctoDatadogDbm.query(PlainRepo, "SELECT current_query()", [])
              result
            end
          ] do
        first = Tracer.with_span("a", do: text(run.()))
        second = Tracer.with_span("b", do: text(run.()))

        assert first =~ ~r/\A\/\*dddbs='test-db',ddps='test-app',traceparent='00-[0-9a-f]{32}-/
        assert first =~ ~r/\*\/ SELECT current_query\(\)\z/
        refute first == second
      end
    end

    test "without a span the comment is service-only" do
      assert text(EctoDatadogDbm.query!(PlainRepo, "SELECT current_query()")) ==
               "/*dddbs='test-db',ddps='test-app'*/ SELECT current_query()"
    end

    test "a :dbm option overrides the Repo config" do
      result = EctoDatadogDbm.query!(PlainRepo, "SELECT current_query()", [], dbm: @opts)
      assert text(result) == "/*dddbs='svc',dde='test'*/ SELECT current_query()"
    end

    test "raises without a :dbm config or option" do
      defmodule NoDbmRepo do
        def config, do: []
      end

      assert_raise ArgumentError, fn -> EctoDatadogDbm.query(NoDbmRepo, "SELECT 1") end
    end

    test "returns errors from query/4" do
      assert {:error, %Postgrex.Error{}} = EctoDatadogDbm.query(PlainRepo, "SELEC 1")
    end
  end

  describe "query/4 and query!/4 on a Repo with the pool" do
    test "are commented once, by the pool, with a fresh traceparent" do
      first =
        Tracer.with_span("a", do: text(EctoDatadogDbm.query!(Repo, "SELECT current_query()")))

      {:ok, second} =
        Tracer.with_span("b", do: EctoDatadogDbm.query(Repo, "SELECT current_query()"))

      assert first =~
               ~r/\A\/\*dddbs='test-db',dde='test',ddps='test-app',ddpv='1.0.0',traceparent='00-/

      assert length(:binary.matches(first, "/*")) == 1
      refute first == text(second)
    end
  end
end
