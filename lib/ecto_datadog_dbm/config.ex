defmodule EctoDatadogDbm.Config do
  @moduledoc """
  Static service tags injected into every statement.
  """

  @keys [:dddb, :dddbs, :dde, :ddh, :ddps, :ddpv]

  defstruct @keys

  @type t :: %__MODULE__{}

  @doc "Builds the config from keyword options; `:dddbs` is required."
  @spec new!(keyword()) :: t()
  def new!(opts) do
    config = struct!(__MODULE__, Keyword.take(opts, @keys))

    if config.dddbs in [nil, ""] do
      raise ArgumentError, "the :dddbs option is required in the :dbm configuration"
    end

    config
  end
end
