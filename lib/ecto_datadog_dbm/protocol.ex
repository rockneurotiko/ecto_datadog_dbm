defmodule EctoDatadogDbm.Protocol do
  @moduledoc """
  `DBConnection` callback module wrapping `Postgrex.Protocol`.

  The connection state is `{comment, postgrex_state}`. The comment is prepended
  to the statement sent to the server, and the original statement is restored on
  returned queries and `Postgrex.Error` structs so caches, telemetry and error
  reports keep seeing the SQL as written.
  """

  @behaviour DBConnection

  alias EctoDatadogDbm.{Comment, Config}

  @pg Postgrex.Protocol

  @impl true
  def connect(opts) do
    dbm = Keyword.get(opts, :dbm) || raise ArgumentError, "the :dbm configuration is required"
    comment = dbm |> Config.new!() |> Comment.build()

    with {:ok, state} <- @pg.connect(opts), do: {:ok, {comment, state}}
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
  def handle_commit(opts, {comment, state}), do: wrap(@pg.handle_commit(opts, state), comment)

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

  defp with_comment(%{statement: statement} = query, comment),
    do: %{query | statement: Comment.prefix(statement, comment)}

  defp with_comment(query, _comment), do: query

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
