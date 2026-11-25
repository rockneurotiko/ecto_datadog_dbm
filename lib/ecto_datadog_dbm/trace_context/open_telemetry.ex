defmodule EctoDatadogDbm.TraceContext.OpenTelemetry do
  @moduledoc """
  Reads the current OpenTelemetry span.

  Returns `:none` when `opentelemetry_api` is not available, there is no active
  span, or the ids are invalid. When the calling process has no span, the
  `$callers` chain is consulted through `opentelemetry_process_propagator` if
  that package is available, so `Task` processes see their caller's span.
  """

  @behaviour EctoDatadogDbm.TraceContext

  @tracer :otel_tracer
  @span :otel_span
  @propagator OpentelemetryProcessPropagator

  @impl true
  def current do
    if Code.ensure_loaded?(@tracer) and Code.ensure_loaded?(@span) do
      case call(@tracer, :current_span_ctx, []) do
        :undefined -> to_ctx(from_callers())
        span_ctx -> to_ctx(span_ctx)
      end
    else
      :none
    end
  end

  defp from_callers do
    with true <- Code.ensure_loaded?(@propagator),
         ctx when ctx != :undefined <- call(@propagator, :fetch_parent_ctx, [1, :"$callers"]) do
      call(@tracer, :current_span_ctx, [ctx])
    else
      _ -> :undefined
    end
  end

  defp to_ctx(span_ctx) when span_ctx in [nil, :undefined], do: :none

  defp to_ctx(span_ctx) do
    with true <- call(@span, :is_valid, [span_ctx]),
         %{otel_trace_id: trace_id, otel_span_id: span_id, otel_trace_flags: flags} <-
           call(@span, :hex_span_ctx, [span_ctx]),
         true <- valid_hex?(trace_id, 32) and valid_hex?(span_id, 16) do
      {:ok, %{trace_id: trace_id, span_id: span_id, sampled?: flags == "01"}}
    else
      _ -> :none
    end
  end

  defp valid_hex?(id, size),
    do: is_binary(id) and id =~ ~r/\A[0-9a-f]{#{size}}\z/ and id != String.duplicate("0", size)

  # Applied dynamically so a build without opentelemetry_api has no undefined-module warnings.
  defp call(module, function, args), do: apply(module, function, args)
end
