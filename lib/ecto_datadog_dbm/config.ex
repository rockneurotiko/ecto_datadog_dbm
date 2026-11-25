defmodule EctoDatadogDbm.Config do
  @moduledoc """
  Validated settings: the static service tags and the injection mode.

  Options: `:mode` (`:disabled`, `:service` or `:full`), `:traceparent`
  (`:unnamed`, `:sampled` or `:always`), and the tags `:dddb`, `:dddbs`,
  `:dde`, `:ddh`, `:ddps`, `:ddpv`, and `:trace_context`, a module implementing
  `EctoDatadogDbm.TraceContext` (default `EctoDatadogDbm.TraceContext.OpenTelemetry`).

  Unset options fall back to the environment: `DD_DBM_PROPAGATION_MODE`
  (`disabled`, `service` or `full`), `DD_ENV` (`:dde`), `DD_SERVICE`
  (`:ddps`) and `DD_VERSION` (`:ddpv`). Explicit options always win. When
  neither gives a mode it is `:service`, and `:traceparent` defaults to
  `:unnamed`. `:dddbs` has no default and is required unless the mode is
  `:disabled`.
  """

  @modes [:disabled, :service, :full]
  @policies [:unnamed, :sampled, :always]
  @tag_keys [:dddb, :dddbs, :dde, :ddh, :ddps, :ddpv]
  @env_tags [dde: "DD_ENV", ddps: "DD_SERVICE", ddpv: "DD_VERSION"]

  defstruct [:mode, :traceparent, :trace_context | @tag_keys]

  @type t :: %__MODULE__{}

  @doc false
  def tag_keys, do: @tag_keys

  @doc "Builds the config from keyword options, raising `ArgumentError` when invalid."
  @spec new!(keyword()) :: t()
  def new!(opts) do
    mode = fetch_mode(opts)
    policy = Keyword.get(opts, :traceparent, :unnamed)

    unless policy in @policies do
      raise ArgumentError,
            "invalid :traceparent option #{inspect(policy)}, expected one of #{inspect(@policies)}"
    end

    trace_context = fetch_trace_context(opts)
    tags = Map.new(@tag_keys, fn key -> {key, Keyword.get(opts, key, env_default(key))} end)

    if mode != :disabled and tags.dddbs in [nil, ""] do
      raise ArgumentError, "the :dddbs option is required in the :dbm configuration"
    end

    struct!(
      __MODULE__,
      Map.merge(tags, %{mode: mode, traceparent: policy, trace_context: trace_context})
    )
  end

  defp fetch_trace_context(opts) do
    module = Keyword.get(opts, :trace_context, EctoDatadogDbm.TraceContext.OpenTelemetry)

    unless is_atom(module) and Code.ensure_loaded?(module) and
             function_exported?(module, :current, 0) do
      raise ArgumentError,
            "invalid :trace_context option #{inspect(module)}, expected a module exporting current/0"
    end

    module
  end

  defp fetch_mode(opts) do
    case Keyword.fetch(opts, :mode) do
      {:ok, mode} when mode in @modes ->
        mode

      {:ok, mode} ->
        raise ArgumentError,
              "invalid :mode option #{inspect(mode)}, expected one of #{inspect(@modes)}"

      :error ->
        env_mode()
    end
  end

  defp env_mode do
    case System.get_env("DD_DBM_PROPAGATION_MODE") do
      value when value in [nil, ""] ->
        :service

      value ->
        Enum.find(@modes, &(Atom.to_string(&1) == value)) ||
          raise ArgumentError,
                "invalid DD_DBM_PROPAGATION_MODE #{inspect(value)}, expected one of disabled, service, full"
    end
  end

  defp env_default(key) do
    with name when is_binary(name) <- @env_tags[key], do: System.get_env(name)
  end
end
