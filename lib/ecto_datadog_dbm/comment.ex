defmodule EctoDatadogDbm.Comment do
  @moduledoc """
  Builds the leading `/*k='v',...*/` comment and prepends it to a statement.
  """

  alias EctoDatadogDbm.Config

  @doc """
  Builds the comment text, or `""` when no key has a value.

  Only the tag keys are used. Returns `""` when the mode is `:disabled`.
  Keys are sorted, nil/empty values skipped, and every character outside
  `[A-Za-z0-9_.~-]` is percent-encoded so a value can never close the comment.
  The trace context and options are accepted for forward compatibility and
  are currently ignored.
  """
  @spec build(Config.t(), map() | nil, keyword()) :: String.t()
  def build(config, ctx \\ nil, opts \\ [])
  def build(%Config{mode: :disabled}, _ctx, _opts), do: ""

  def build(%Config{} = config, _ctx, _opts) do
    config
    |> tags()
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Enum.sort()
    |> Enum.map_join(",", fn {key, value} -> "#{key}='#{encode(value)}'" end)
    |> case do
      "" -> ""
      body -> "/*" <> body <> "*/"
    end
  end

  defp tags(config), do: Enum.map(Config.tag_keys(), &{&1, Map.fetch!(config, &1)})

  @doc "Prepends the comment to a statement; nil, empty and unusable input pass through."
  @spec prefix(iodata() | nil, String.t()) :: iodata() | nil
  def prefix(statement, comment) when statement in [nil, "", []] or comment == "", do: statement
  def prefix(statement, comment), do: [comment, " ", statement]

  defp encode(value), do: value |> to_string() |> URI.encode(&unreserved?/1)

  defp unreserved?(char),
    do: char in ?a..?z or char in ?A..?Z or char in ?0..?9 or char in ~c"_.~-"
end
