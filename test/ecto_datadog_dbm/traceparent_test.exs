defmodule EctoDatadogDbm.TraceparentTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  require OpenTelemetry.Tracer, as: Tracer

  alias EctoDatadogDbm.{Comment, Config}
  alias EctoDatadogDbm.Test.{Env, Repo}
  alias EctoDatadogDbm.TraceContext.OpenTelemetry, as: OtelContext

  @traceparent ~r/traceparent='00-[0-9a-f]{32}-[0-9a-f]{16}-(01|00)'/

  setup do
    Env.clear!()
    on_exit(fn -> Tracer.set_current_span(:undefined) end)
  end

  defp current_query, do: from(c in "pg_class", select: fragment("current_query()"), limit: 1)

  defp server_text(run), do: run.() |> then(fn {:ok, %{rows: [[sql]]}} -> sql end)

  defp unnamed_variants do
    [
      fn -> Repo.query("SELECT current_query()") end,
      fn -> {:ok, %{rows: [[Repo.query!("SELECT current_query()").rows |> hd() |> hd()]]}} end,
      fn -> Repo.query("SELECT current_query()", [], prepare: :unnamed) end,
      fn -> Repo.query("SELECT current_query()", [], query_cache: false) end
    ]
  end

  test "Comment.build adds a sorted traceparent only for unnamed statements in :full mode" do
    ctx = %{
      trace_id: String.duplicate("a", 32),
      span_id: String.duplicate("b", 16),
      sampled?: true
    }

    full = Config.new!(mode: :full, dddbs: "svc")
    tp = "traceparent='00-#{ctx.trace_id}-#{ctx.span_id}-01'"

    assert Comment.build(full, ctx, named?: false) == "/*dddbs='svc',#{tp}*/"
    assert Comment.build(full, ctx, named?: true) == "/*dddbs='svc'*/"
    assert Comment.build(full, nil, named?: false) == "/*dddbs='svc'*/"

    assert Comment.build(Config.new!(mode: :service, dddbs: "svc"), ctx, named?: false) ==
             "/*dddbs='svc'*/"

    unsampled = Comment.build(full, %{ctx | sampled?: false}, named?: false)
    assert unsampled =~ "-00'"
  end

  test "unnamed statements carry a fresh traceparent per span" do
    for run <- unnamed_variants() do
      first = Tracer.with_span("a", do: server_text(run))
      second = Tracer.with_span("b", do: server_text(run))

      assert first =~ ~r/\A\/\*.*traceparent='00-[0-9a-f]{32}-[0-9a-f]{16}-01'.*\*\/ SELECT/
      assert second =~ @traceparent
      refute first == second
    end
  end

  test "an unsampled span yields flag 00" do
    Tracer.set_current_span(:otel_tracer.from_remote_span(1, 2, 0))

    assert server_text(fn -> Repo.query("SELECT current_query()") end) =~
             "-0000000000000002-00'"
  end

  test "named statements carry only the static comment" do
    Tracer.with_span "work" do
      for _ <- 1..2 do
        assert [text] = Repo.all(current_query())
        assert text =~ "/*dddbs='test-db',dde='test',ddps='test-app',ddpv='1.0.0'*/ SELECT"
        refute text =~ "traceparent"
      end
    end
  end

  test "no span means no traceparent and no error" do
    text = server_text(fn -> Repo.query("SELECT current_query()") end)

    assert text =~ "/*dddbs='test-db',dde='test',ddps='test-app',ddpv='1.0.0'*/ SELECT"
    refute text =~ "traceparent"
  end

  test "errors keep the original statement" do
    Tracer.with_span "work" do
      assert {:error, %Postgrex.Error{query: "SELEC 1"}} = Repo.query("SELEC 1")
    end
  end

  test "a Task under a span carries that span's trace" do
    Tracer.with_span "parent" do
      %{trace_id: trace_id} = elem(OtelContext.current(), 1)

      text =
        Task.async(fn -> server_text(fn -> Repo.query("SELECT current_query()") end) end)
        |> Task.await()

      assert text =~ "traceparent='00-#{trace_id}-"
    end
  end

  test "trace_context must be a module exporting current/0" do
    for bad <- [NoSuchModule, Enum, "x"] do
      assert_raise ArgumentError, ~r/:trace_context/, fn ->
        Config.new!(dddbs: "s", trace_context: bad)
      end
    end
  end
end
