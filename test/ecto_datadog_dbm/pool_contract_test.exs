defmodule EctoDatadogDbm.PoolContractTest do
  use ExUnit.Case, async: true

  # A Repo's `:pool` option is an implicit contract: DBConnection calls child_spec/1 and
  # the DBConnection.Pool callbacks on the module. The contract is whatever
  # DBConnection.ConnectionPool exports beyond its GenServer plumbing (start_link/1 is
  # started by its own child_spec/1).
  #
  # Negative proof: if a db_connection upgrade adds a public function to
  # ConnectionPool, or a Pool callback is deleted from EctoDatadogDbm.Pool, the missing
  # name is listed in the assertion failure below.
  test "EctoDatadogDbm.Pool exports every public function a Repo needs from ConnectionPool" do
    plumbing = [start_link: 1] ++ GenServer.behaviour_info(:callbacks)

    needed =
      Enum.uniq(
        DBConnection.Pool.behaviour_info(:callbacks) ++
          (DBConnection.ConnectionPool.__info__(:functions) -- plumbing)
      )

    assert {:checkout, 3} in needed
    assert {:child_spec, 1} in needed

    missing = Enum.reject(needed, &(&1 in EctoDatadogDbm.Pool.__info__(:functions)))
    assert missing == []
  end
end
