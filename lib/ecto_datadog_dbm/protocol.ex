defmodule EctoDatadogDbm.Protocol do
  @moduledoc """
  `DBConnection` callback module wrapping `Postgrex.Protocol`.

  Unnamed statements get a per-call comment with the caller's trace context;
  named statements keep the static comment, since their text is sent only once.

  `COMMIT` carries the static comment through Postgrex's `:commit_comment` option
  (a traceparent is not added: a transaction has no statement of its own to link).
  `BEGIN` and `ROLLBACK` stay unprefixed because Postgrex offers no comment hook for them.

  The connection state is `{{config, comment}, postgrex_state}`. The comment is prepended
  to the statement sent to the server, and the original statement is restored on
  returned queries and `Postgrex.Error` structs so caches, telemetry and error
  reports keep seeing the SQL as written.
  """

  @behaviour DBConnection

  alias EctoDatadogDbm.Comment

  @pg Postgrex.Protocol

  @impl true
  def connect(opts) do
    dbm = {Keyword.fetch!(opts, :dbm), Keyword.fetch!(opts, :dbm_comment)}

    with {:ok, state} <- @pg.connect(opts), do: {:ok, {dbm, state}}
  end

  @impl true
  def disconnect(err, {_, state}), do: @pg.disconnect(err, state)

  @impl true
  def checkout({comment, state}), do: wrap(@pg.checkout(state), comment)

  @impl true
  def ping({comment, state}), do: wrap(@pg.ping(state), comment)

  @impl true
  def handle_begin(opts, {comment, state}), do: wrap(@pg.handle_begin(opts, state), comment)

  @impl true
  def handle_commit(opts, {{_config, static} = dbm, state}) do
    opts = put_commit_comment(opts, static)
    wrap(@pg.handle_commit(opts, state), dbm)
  end

  @impl true
  def handle_rollback(opts, {comment, state}),
    do: wrap(@pg.handle_rollback(opts, state), comment)

  @impl true
  def handle_status(opts, {comment, state}), do: wrap(@pg.handle_status(opts, state), comment)

  @impl true
  def handle_prepare(query, opts, {comment, state}) do
    query
    |> with_comment(comment)
    |> @pg.handle_prepare(opts, state)
    |> restore(query, comment)
  end

  @impl true
  def handle_execute(query, params, opts, {comment, state}) do
    query
    |> with_comment(comment)
    |> @pg.handle_execute(params, opts, state)
    |> restore(query, comment)
  end

  @impl true
  def handle_declare(query, params, opts, {comment, state}) do
    query
    |> with_comment(comment)
    |> @pg.handle_declare(params, opts, state)
    |> restore(query, comment)
  end

  @impl true
  def handle_close(query, opts, {comment, state}),
    do: wrap(@pg.handle_close(query, opts, state), comment)

  @impl true
  def handle_fetch(query, cursor, opts, {comment, state}),
    do: wrap(@pg.handle_fetch(query, cursor, opts, state), comment)

  @impl true
  def handle_deallocate(query, cursor, opts, {comment, state}),
    do: wrap(@pg.handle_deallocate(query, cursor, opts, state), comment)

  # Postgrex builds `/* comment */\nCOMMIT` itself and wants the bare comment text.
  # The static comment is percent-encoded, so it never contains `*/`.
  defp put_commit_comment(opts, "/*" <> _ = static),
    do: Keyword.put(opts, :commit_comment, binary_part(static, 2, byte_size(static) - 4))

  defp put_commit_comment(opts, _static), do: opts

  defp with_comment(%{statement: statement} = query, {config, static}),
    do: %{query | statement: Comment.prefix(statement, comment_for(query, config, static))}

  defp with_comment(query, _comment), do: query

  defp comment_for(query, %{mode: :full, trace_context: trace_context} = config, static) do
    with true <- unnamed?(query), {:ok, ctx} <- trace_context.current() do
      Comment.build(config, ctx, named?: false)
    else
      _ -> static
    end
  end

  defp comment_for(_query, _config, static), do: static

  defp unnamed?(%Postgrex.TextQuery{}), do: true
  defp unnamed?(%Postgrex.Query{name: ""}), do: true
  defp unnamed?(_query), do: false

  defp restore(result, original, comment) do
    result
    |> Tuple.to_list()
    |> Enum.map(&restore_element(&1, original))
    |> List.to_tuple()
    |> wrap(comment)
  end

  defp restore_element(%{statement: _} = query, %{statement: statement}),
    do: %{query | statement: statement}

  defp restore_element(%Postgrex.Error{query: query} = error, %{statement: statement})
       when query != nil,
       do: %{error | query: statement}

  defp restore_element(element, _original), do: element

  # Every DBConnection result tuple carries the new state last.
  defp wrap(result, comment) do
    last = tuple_size(result)
    put_elem(result, last - 1, {comment, elem(result, last - 1)})
  end
end
