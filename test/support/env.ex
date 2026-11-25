defmodule EctoDatadogDbm.Test.Env do
  @moduledoc false

  @vars ~w(DD_DBM_PROPAGATION_MODE DD_ENV DD_SERVICE DD_VERSION)

  @doc "Unsets the DD_* variables for the calling test and restores them on exit."
  def clear! do
    saved = Map.new(@vars, &{&1, System.get_env(&1)})
    Enum.each(@vars, &System.delete_env/1)

    ExUnit.Callbacks.on_exit(fn ->
      Enum.each(saved, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end)
  end
end
