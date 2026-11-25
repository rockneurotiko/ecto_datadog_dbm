defmodule EctoDatadogDbm.Protocol do
  @moduledoc """
  `DBConnection` callback module wrapping `Postgrex.Protocol`.

  Unnamed statements get a per-call comment with the caller's trace context;
  named statements keep the static comment, since their text is sent only once.
  Under the `:sampled` and `:always` traceparent policies a named statement is executed
  as an unnamed copy with the full comment (for `:sampled` only in a sampled trace), and
  the original named query is returned, so the named prepared statement is neither
  re-parsed nor replaced and Ecto's cache entry stays valid. A statement that was just
  prepared in the same call and still holds the connection locked (e.g. the first
  `insert_all` of a shape) keeps the static comment for that run.

  The lock check (`locked?/1`) relies on Postgrex's internal connection state shape
  (`postgres: {status, ref}`, verified against the installed Postgrex). If that shape
  changed, the first execution of a freshly prepared statement would fail, so the test
  that runs the first `insert_all` of a shape inside a transaction under `:sampled` and
  `:always` must stay.

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
    run(query, comment, state, &@pg.handle_execute(&1, params, opts, state))
  end

  @impl true
  def handle_declare(query, params, opts, {comment, state}) do
    run(query, comment, state, &@pg.handle_declare(&1, params, opts, state))
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

  # Executes `fun` with the query to send. A named query that must carry a traceparent
  # (`:sampled` and `:always` policies) is sent as an unnamed copy, so the named prepared
  # statement is neither re-parsed nor replaced, and the original struct is returned.
  # A freshly prepared named query leaves the connection locked to it until it is executed
  # (`postgres: {status, ref}`), so that first execution keeps the static comment.
  defp run(query, {config, _static} = comment, state, fun) do
    case unnamed_copy(query, config, state) do
      {:ok, copy} -> copy |> fun.() |> restore(query, comment, fn _ -> query end)
      :error -> query |> with_comment(comment) |> fun.() |> restore(query, comment)
    end
  end

  defp unnamed_copy(
         %Postgrex.Query{name: name, statement: statement} = query,
         %{mode: :full, traceparent: policy, trace_context: trace_context} = config,
         state
       )
       when name != "" and policy in [:sampled, :always] do
    with false <- locked?(state),
         {:ok, %{sampled?: sampled?} = ctx} <- trace_context.current(),
         true <- policy == :always or sampled? do
      comment = Comment.build(config, ctx, named?: false)
      {:ok, %{query | name: "", ref: nil, statement: Comment.prefix(statement, comment)}}
    else
      _ -> :error
    end
  end

  defp unnamed_copy(_query, _config, _state), do: :error

  # Depends on Postgrex internals; see the moduledoc.
  defp locked?(%{postgres: {_, _}}), do: true
  defp locked?(_state), do: false

  defp unnamed?(%Postgrex.TextQuery{}), do: true
  defp unnamed?(%Postgrex.Query{name: ""}), do: true
  defp unnamed?(_query), do: false

  defp restore(result, original, comment),
    do: restore(result, original, comment, &restore_statement(&1, original))

  defp restore(result, original, comment, on_query) do
    result
    |> Tuple.to_list()
    |> Enum.map(fn
      %Postgrex.Query{} = query -> on_query.(query)
      %Postgrex.TextQuery{} = query -> on_query.(query)
      element -> restore_element(element, original)
    end)
    |> List.to_tuple()
    |> wrap(comment)
  end

  defp restore_statement(%{statement: _} = query, %{statement: statement}),
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
