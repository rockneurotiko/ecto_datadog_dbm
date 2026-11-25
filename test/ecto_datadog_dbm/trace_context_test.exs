defmodule EctoDatadogDbm.TraceContextTest do
  use ExUnit.Case, async: false

  require OpenTelemetry.Tracer, as: Tracer

  alias EctoDatadogDbm.TraceContext.OpenTelemetry, as: OtelContext

  @hex_trace_id "0af7651916cd43dd8448eb211c80319c"
  @hex_span_id "b7ad6b7169203331"

  defp remote_span(opts) do
    :otel_tracer.from_remote_span(
      Keyword.get(opts, :trace_id, 0x0AF7651916CD43DD8448EB211C80319C),
      Keyword.get(opts, :span_id, 0xB7AD6B7169203331),
      Keyword.get(opts, :trace_flags, 1)
    )
  end

  setup do
    on_exit(fn -> Tracer.set_current_span(:undefined) end)
  end

  test "behaviour shape: current/0 returns :none or a well-formed context" do
    assert {:current, 0} in OtelContext.module_info(:exports)
    assert :none = OtelContext.current()

    Tracer.with_span "work" do
      assert {:ok, %{trace_id: trace_id, span_id: span_id, sampled?: true}} =
               OtelContext.current()

      assert trace_id =~ ~r/\A[0-9a-f]{32}\z/
      assert span_id =~ ~r/\A[0-9a-f]{16}\z/
    end
  end

  test "reports the active span's ids" do
    Tracer.set_current_span(remote_span(trace_flags: 1))

    assert {:ok, %{trace_id: @hex_trace_id, span_id: @hex_span_id, sampled?: true}} =
             OtelContext.current()
  end

  test "an unsampled span has sampled? false" do
    Tracer.set_current_span(remote_span(trace_flags: 0))
    assert {:ok, %{sampled?: false}} = OtelContext.current()
  end

  test "all-zero ids are ignored" do
    Tracer.set_current_span(remote_span(trace_id: 0, span_id: 0))
    assert :none = OtelContext.current()
  end

  test "a Task resolves its caller's span through $callers" do
    Tracer.with_span "parent" do
      {:ok, expected} = OtelContext.current()
      assert {:ok, ^expected} = Task.async(&OtelContext.current/0) |> Task.await()
    end
  end

  test "a Task without a caller span gets :none" do
    assert :none = Task.async(&OtelContext.current/0) |> Task.await()
  end
end
