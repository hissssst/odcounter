defmodule ODCounterTest do
  use ExUnit.Case, async: true
  if Version.match?(System.version(), "~> 1.19") do
    doctest ODCounter
  else
    doctest ODCounter, except: [remove_schema: 1]
  end

  require ODCounter

  setup do
    {:ok, name: make_ref()}
  end

  test "Double init_schema" do
    ODCounter.init_schema(:double_init_schema)

    assert_raise ArgumentError, fn ->
      ODCounter.init_schema(:double_init_schema)
    end
  end

  test "Remove deletes runtime keys", %{name: name} do
    ODCounter.init_schema(:remove_rt_del)
    ODCounter.new(:remove_rt_del, name)

    rt_key = :rt_key
    ODCounter.add(:remove_rt_del, name, rt_key, 123)
    ODCounter.add(:remove_rt_del, name, :ct_key, 100)

    ODCounter.delete(:remove_rt_del, name)

    assert :removed == :persistent_term.get({:odcoutner, :remove_rt_del, rt_key}, :removed)
  end

  test "Info works", %{name: name} do
    ODCounter.init_schema(:info_test, runtime_size: 10)
    ODCounter.new(:info_test, name)

    rt_key = :rt_key
    ODCounter.add(:info_test, name, rt_key, 123)
    ODCounter.add(:info_test, name, :ct_key, 100)

    assert %{
      counters_info: %{size: 11},
      current_max_index: 3,
      compile_time_indexes: %{ct_key: 1},
      runtime_indexes: %{rt_key: 3}
    } = ODCounter.info(:info_test, name)
  end

  test "Getting runtime works", %{name: name} do
    ODCounter.init_schema(:rt_get_test, runtime_size: 10)
    ODCounter.new(:rt_get_test, name)

    rt_key = :rt_key
    ODCounter.add(:rt_get_test, name, rt_key, 999)
    ODCounter.add(:rt_get_test, name, :ct_key, 100)

    assert 999 = ODCounter.get(:rt_get_test, name, rt_key)
    assert 100 = ODCounter.get(:rt_get_test, name, :ct_key)
  end

  test "sub works", %{name: name} do
    ODCounter.init_schema(:sub_test, runtime_size: 10)
    ODCounter.new(:sub_test, name)

    rt_key = :rt_key
    ODCounter.add(:sub_test, name, rt_key, 999)
    ODCounter.add(:sub_test, name, :ct_key, 100)

    ODCounter.sub(:sub_test, name, rt_key, 100)
    ODCounter.sub(:sub_test, name, :ct_key, 100)

    assert 899 = ODCounter.get(:sub_test, name, rt_key)
    assert 0 = ODCounter.get(:sub_test, name, :ct_key)
  end

  test "Compilation fails" do
    ODCounter.init_schema(:compilation_fails)
    ODCounter.new(:compilation_fails, :new)

    assert_raise CompileError, fn ->
      Code.eval_quoted(quote do
        require ODCounter
        x = :compilation_fails
        ODCounter.add(x, :name, :key)
      end)
    end
  end
end
