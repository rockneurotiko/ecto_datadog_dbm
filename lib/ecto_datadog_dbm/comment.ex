defmodule EctoDatadogDbm.Comment do
  @moduledoc """
  Builds the leading `/*k='v',...*/` comment and prepends it to a statement.
  """

  alias EctoDatadogDbm.Config

  @doc """
  Builds the comment text, or `""` when no key has a value.

  Returns `""` when the mode is `:disabled`. In `:full` mode a trace context
  given for an unnamed statement (`named?: false`) adds a `traceparent` key;
  named statements only get the static tags, as their text is sent once.
  Keys are sorted, nil/empty values skipped, and every character outside
  `[A-Za-z0-9_.~-]` is percent-encoded so a value can never close the comment.
  """
  @spec build(Config.t(), map() | nil, keyword()) :: String.t()
  def build(config, ctx \\ nil, opts \\ [])
  def build(%Config{mode: :disabled}, _ctx, _opts), do: ""

  def build(%Config{} = config, ctx, opts) do
    config
    |> tags()
    |> add_traceparent(config, ctx, opts)
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Enum.sort()
    |> Enum.map_join(",", fn {key, value} -> "#{key}='#{encode(value)}'" end)
    |> case do
      "" -> ""
      body -> "/*" <> body <> "*/"
    end
  end

  defp add_traceparent(tags, %Config{mode: :full}, %{} = ctx, opts) do
    if Keyword.get(opts, :named?, true), do: tags, else: [{:traceparent, traceparent(ctx)} | tags]
  end

  defp add_traceparent(tags, _config, _ctx, _opts), do: tags

  defp traceparent(%{trace_id: trace_id, span_id: span_id, sampled?: sampled?}),
    do: "00-#{trace_id}-#{span_id}-#{if sampled?, do: "01", else: "00"}"

  defp tags(config), do: Enum.map(Config.tag_keys(), &{&1, Map.fetch!(config, &1)})

  @doc "Prepends the comment to a statement; empty, `nil` and non-iodata input pass through."
  @spec prefix(iodata() | nil, String.t()) :: iodata() | nil
  def prefix(statement, ""), do: statement

  def prefix(statement, comment),
    do: if(blank?(statement), do: statement, else: [comment, " ", statement])

  # IO.iodata_length/1 raises on anything that is not valid iodata.
  defp blank?(statement) do
    IO.iodata_length(statement) == 0
  rescue
    ArgumentError -> true
  end

  defp encode(value), do: value |> to_string() |> URI.encode(&unreserved?/1)

  defp unreserved?(char),
    do: char in ?a..?z or char in ?A..?Z or char in ?0..?9 or char in ~c"_.~-"
end
