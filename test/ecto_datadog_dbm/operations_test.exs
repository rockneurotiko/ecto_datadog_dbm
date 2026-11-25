defmodule EctoDatadogDbm.OperationsTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Multi
  alias EctoDatadogDbm.Test.{DisabledRepo, Env, PlainRepo, Repo}

  @comment "/*dddbs='test-db',dde='test',ddps='test-app',ddpv='1.0.0'*/"

  @inner @comment |> String.trim_leading("/*") |> String.trim_trailing("*/")

  defmodule Item do
    use Ecto.Schema
    import Ecto.Changeset

    schema "dbm_items" do
      field(:name, :string)
    end

    def changeset(item, attrs) do
      item |> cast(attrs, [:name]) |> unique_constraint(:name, name: :dbm_items_name_key)
    end
  end

  setup do
    Env.clear!()

    Repo.query!("CREATE TABLE IF NOT EXISTS dbm_items (id serial PRIMARY KEY, name text UNIQUE)")
    Repo.query!("TRUNCATE dbm_items")
    on_exit(fn -> PlainRepo.query!("DROP TABLE IF EXISTS dbm_items") end)
    :ok
  end

  # An idle or idle-in-transaction backend reports the last statement it ran.
  defp last_query(pid) do
    %{rows: [[query]]} =
      PlainRepo.query!("SELECT query FROM pg_stat_activity WHERE pid = $1", [pid])

    query
  end

  defp pinned(fun) do
    Repo.checkout(fn ->
      %{rows: [[pid]]} = Repo.query!("SELECT pg_backend_pid()")
      fun.(pid)
    end)
  end

  defp insert!(name), do: Repo.insert!(%Item{name: name})

  test "single-statement writes carry the prefix" do
    pinned(fn pid ->
      item = insert!("a")
      assert last_query(pid) =~ ~s(#{@comment} INSERT INTO "dbm_items")

      item |> Item.changeset(%{name: "b"}) |> Repo.update!()
      assert last_query(pid) =~ ~s(#{@comment} UPDATE "dbm_items")

      Repo.insert_all(Item, [%{name: "c"}, %{name: "d"}])
      assert last_query(pid) =~ ~s(#{@comment} INSERT INTO "dbm_items")

      Repo.update_all(from(i in Item, where: false), set: [name: "z"])
      assert last_query(pid) =~ ~s(#{@comment} UPDATE "dbm_items")

      Repo.delete!(item)
      assert last_query(pid) =~ ~s(#{@comment} DELETE FROM "dbm_items")

      Repo.delete_all(from(i in Item, where: false))
      assert last_query(pid) =~ ~s(#{@comment} DELETE FROM "dbm_items")
    end)
  end

  test "Multi statements and COMMIT carry the prefix; BEGIN and ROLLBACK do not" do
    pinned(fn pid ->
      Repo.transaction(fn -> assert last_query(pid) == "BEGIN" end)
      assert last_query(pid) == "/* #{@inner} */
COMMIT"

      Repo.transaction(fn -> Repo.rollback(:nope) end)
      assert last_query(pid) == "ROLLBACK"

      multi =
        Multi.new()
        |> Multi.insert(:item, %Item{name: "m"})
        |> Multi.run(:seen, fn _, _ -> {:ok, last_query(pid)} end)

      {:ok, %{seen: seen}} = Repo.transaction(multi)
      assert seen =~ ~s(#{@comment} INSERT INTO "dbm_items")

      assert last_query(pid) == "/* #{@inner} */\nCOMMIT"
    end)
  end

  test "Repo.stream statements carry the prefix" do
    sql = from(i in Item, select: fragment("current_query()"))
    insert!("s")

    {:ok, [text]} = Repo.transaction(fn -> sql |> Repo.stream() |> Enum.take(1) end)
    assert text =~ "#{@comment} SELECT current_query()"
  end

  test "a unique violation maps to a changeset error and errors hold the original SQL" do
    insert!("dup")

    assert {:error, changeset} = %Item{} |> Item.changeset(%{name: "dup"}) |> Repo.insert()
    assert {"has already been taken", _} = changeset.errors[:name]

    sql = "INSERT INTO dbm_missing (name) VALUES ('dup')"
    assert {:error, %Postgrex.Error{query: ^sql}} = Repo.query(sql)
  end

  test "a unique violation at execute time raises with no comment in the error" do
    insert!("dup")
    plain = "dbm_items"

    error = assert_raise Postgrex.Error, fn -> Repo.insert_all(Item, [%{name: "dup"}]) end

    # Postgrex leaves `query` nil for errors raised while executing a prepared statement,
    # so there is no statement text to carry the comment.
    assert error.query == nil
    refute Exception.message(error) =~ "dddbs"
    assert Exception.message(error) =~ plain
  end

  test "COMMIT is untouched when propagation is disabled" do
    DisabledRepo.checkout(fn ->
      %{rows: [[pid]]} = DisabledRepo.query!("SELECT pg_backend_pid()")
      DisabledRepo.transaction(fn -> :ok end)
      assert last_query(pid) == "COMMIT"
    end)
  end

  test "insert, update and delete stay cached with the static comment" do
    pinned(fn _pid ->
      prepared = fn ->
        %{rows: rows} =
          Repo.query!(
            "SELECT name, prepare_time FROM pg_prepared_statements WHERE name ~ '^ecto_(insert|update|delete)_dbm_items_' ORDER BY name"
          )

        rows
      end

      run = fn n ->
        item = insert!("c#{n}")
        item |> Item.changeset(%{name: "u#{n}"}) |> Repo.update!()
        Repo.delete!(item)
      end

      run.(1)
      [_, _, _] = rows = prepared.()

      Process.sleep(20)
      run.(2)
      assert rows == prepared.()
    end)
  end
end
