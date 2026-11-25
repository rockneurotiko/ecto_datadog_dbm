defmodule EctoDatadogDbm.CommentTest do
  use ExUnit.Case, async: true

  alias EctoDatadogDbm.{Comment, Config}

  test "sorted, single-quoted, comma separated, nil and empty skipped" do
    config = Config.new!(ddpv: "1.0", dddbs: "svc", dde: "prod", ddh: "", dddb: nil, ddps: "app")

    assert Comment.build(config) ==
             "/*dddbs='svc',dde='prod',ddps='app',ddpv='1.0'*/"
  end

  test "percent-encodes comment terminators and quotes with uppercase hex" do
    config = Config.new!(dddbs: "a*/b'c d")

    assert Comment.build(config) == "/*dddbs='a%2A%2Fb%27c%20d'*/"
  end

  test "encodes newlines, NUL and non-ASCII" do
    config = Config.new!(dddbs: "a\nb\0é")

    assert Comment.build(config) == "/*dddbs='a%0Ab%00%C3%A9'*/"
  end

  test "dddbs is required" do
    assert_raise ArgumentError, ~r/dddbs/, fn -> Config.new!(dde: "prod") end
  end

  test "prefix leaves nil, empty statements and empty comments untouched" do
    assert Comment.prefix(nil, "/*a*/") == nil
    assert Comment.prefix("", "/*a*/") == ""
    assert Comment.prefix("SELECT 1", "") == "SELECT 1"
    assert IO.iodata_to_binary(Comment.prefix(["SELECT", " 1"], "/*a*/")) == "/*a*/ SELECT 1"
  end
end
