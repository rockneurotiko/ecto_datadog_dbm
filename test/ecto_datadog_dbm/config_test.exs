defmodule EctoDatadogDbm.ConfigTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias EctoDatadogDbm.{Comment, Config, Pool}
  alias EctoDatadogDbm.Test.{DisabledRepo, Env, PlainRepo}

  setup do
    Env.clear!()
  end

  describe "validation" do
    test "invalid mode names the option" do
      assert_raise ArgumentError, ~r/:mode/, fn -> Config.new!(mode: :loud, dddbs: "s") end
    end

    test "invalid traceparent policy names the option" do
      assert_raise ArgumentError, ~r/:traceparent/, fn ->
        Config.new!(traceparent: :never, dddbs: "s")
      end
    end

    test "missing dddbs raises in :service and :full" do
      for mode <- [:service, :full] do
        assert_raise ArgumentError, ~r/:dddbs/, fn -> Config.new!(mode: mode) end
      end

      assert_raise ArgumentError, ~r/:dddbs/, fn -> Config.new!([]) end
    end

    test ":disabled never raises" do
      assert %Config{mode: :disabled} = Config.new!(mode: :disabled)
    end

    test "defaults are :service and :unnamed" do
      assert %Config{mode: :service, traceparent: :unnamed} = Config.new!(dddbs: "s")
    end

    test "Pool.child_spec accepts SensitiveData-wrapped input" do
      input = %DBConnection.SensitiveData{data: [dbm: [mode: :disabled]]}
      assert %{id: _} = Pool.child_spec({Postgrex.Protocol, input})

      assert_raise ArgumentError, ~r/:dddbs/, fn ->
        Pool.child_spec(
          {Postgrex.Protocol, %DBConnection.SensitiveData{data: [dbm: [mode: :full]]}}
        )
      end
    end

    test "Pool.child_spec validates at Repo start" do
      assert_raise ArgumentError, ~r/:dddbs/, fn ->
        Pool.child_spec({Postgrex.Protocol, dbm: [mode: :full]})
      end

      assert_raise ArgumentError, ~r/:mode/, fn ->
        Pool.child_spec({Postgrex.Protocol, dbm: [mode: :bogus, dddbs: "s"]})
      end
    end
  end

  describe "environment defaults" do
    test "an explicit nil or empty tag beats the environment default" do
      System.put_env("DD_ENV", "prod")

      for value <- [nil, ""] do
        assert %Config{dde: ^value} = Config.new!(dddbs: "s", dde: value)
      end
    end

    test "apply when options are unset" do
      System.put_env("DD_DBM_PROPAGATION_MODE", "full")
      System.put_env("DD_ENV", "prod")
      System.put_env("DD_SERVICE", "app")
      System.put_env("DD_VERSION", "2.0")

      assert %Config{mode: :full, dde: "prod", ddps: "app", ddpv: "2.0"} =
               Config.new!(dddbs: "s")
    end

    test "explicit options win" do
      System.put_env("DD_DBM_PROPAGATION_MODE", "disabled")
      System.put_env("DD_ENV", "prod")
      System.put_env("DD_SERVICE", "app")
      System.put_env("DD_VERSION", "2.0")

      assert %Config{mode: :service, dde: "dev", ddps: "other", ddpv: "3"} =
               Config.new!(mode: :service, dddbs: "s", dde: "dev", ddps: "other", ddpv: "3")
    end

    test "an invalid mode in the environment raises" do
      System.put_env("DD_DBM_PROPAGATION_MODE", "loud")
      assert_raise ArgumentError, ~r/DD_DBM_PROPAGATION_MODE/, fn -> Config.new!(dddbs: "s") end
    end
  end

  describe "comment" do
    test "nil and empty ddh are omitted" do
      for ddh <- [nil, ""] do
        assert Comment.build(Config.new!(dddbs: "s", ddh: ddh)) == "/*dddbs='s'*/"
      end
    end

    test "mode and policy never leak into the comment" do
      config = Config.new!(mode: :full, traceparent: :always, dddbs: "s")
      assert Comment.build(config) == "/*dddbs='s'*/"
    end

    test ":disabled builds nothing" do
      assert Comment.build(Config.new!(mode: :disabled, dddbs: "s", dde: "x")) == ""
    end
  end

  test ":disabled statements are byte-identical to a Repo without the wrapper" do
    query = from(c in "pg_class", select: fragment("current_query()"), limit: 1)

    assert DisabledRepo.all(query) == PlainRepo.all(query)
    assert DisabledRepo.all(query) == PlainRepo.all(query)
    assert [<<"SELECT current_query()", _::binary>>] = DisabledRepo.all(query)
  end
end
