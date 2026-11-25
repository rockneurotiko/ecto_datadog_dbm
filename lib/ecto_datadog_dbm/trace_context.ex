defmodule EctoDatadogDbm.TraceContext do
  @moduledoc """
  Source of the trace context that is propagated in the comment.

  `current/0` is called in the process that issues the query.
  """

  @type ctx :: %{trace_id: String.t(), span_id: String.t(), sampled?: boolean()}

  @callback current() :: {:ok, ctx()} | :none
end
