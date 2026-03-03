defmodule ODCounter do
  @moduledoc """
  `m::counters` but without ceremony.

  It provides functions similar to those `m::counters` has but instead of indexes
  it uses arbitrary term as keys.

  Every function or macro can be called with arbitrary term as the counter key.
  ODCounter will try it's best to detect the literal at compile time and to
  create an association between the term and index at compile time. However,
  if it is not possible to detect the literal value at compile time,
  the association will be safely stored in `:persistent_term` in runtime.

  It is possible to disable the runtime fallback by setting the `runtime_size` option of `init_schema/2` to 0.
  See `t:init_schema_option/0` for more information

  ## Example

  Lets count how often some user assesses specific features in our system.
  First, we need to initialize the counters schema.
  Think of it as of `CREATE TABLE` in SQL.

  ```elixir
  ODCounter.init_schema(:features_used)
  ```

  Then we need to create state which will hold counters of this schema.
  Think of it as of adding a new row into the SQL table.

  ```elixir
  ODCounter.new(:features_used, "userID:12345")
  ```

  And now we can start counting things.
  In terms of SQL metaphora, it is akin to updating cells in some rows

  ```elixir
  ODCounter.add(:features_used, "userID:12345", :2fa_github_login)
  ODCounter.add(:features_used, "userID:12345", :click_on_suggestions, 2)
  ...
  ODCounter.add(:features_used, "userID:12345", :click_on_suggestions, 1)

  feature_name = detect_the_feature_name(...)
  ODCounter.add(:features_used, "userID:12345", feature_name)
  ```

  Please note that the last `add` call refers to specific counter dynamically.
  Accessing such counters is a little bit slower than accessing counters which
  are stated as literals in the arguments of `get/4`, `add/4` and so on, but
  it is still quite efficient.

  And now let's access what we counted
  ```elixir
  ODCounter.to_map(:features_user, "userID:12345")
  ```

  > #### Warning {: .warning}
  >
  > Any term passed as the counter key will be added to `persistent_term`, and therefore it won't be
  > garbage collected automatically. In order to clear associations table, you must call `remove/1`
  >
  > **Example:**
  > ```
  > very_large_list = Enum.to_list(1..1000)
  > ODCounter.init_schema(:structures)
  > ODCounter.new(:structures, very_big_term) # very_big_term won't be garbage collected now
  > ODCounter.get(:structures, very_big_term, very_large_list) # so is very_large_list now
  > ```
  >
  > This is true for all of the `get/4`, `sub/4`, `add/4`, `atoi/2` and `put/4` macros.

  > #### Tip {: .tip}
  >
  > In order to achieve maximum efficieny, you should pass keys as literals,
  > in the arguments, not variables or function calls
  >
  > **Example:**
  > ```
  > ODCounter.init_schema(:letters)
  > ODCounter.new(:letters, "in the email number 34")
  > ODCounter.add(:letters, "in the email number 34", :a) # fast
  > b = :b
  > ODCounter.add(:letters, "in the email number 34", b) # slow
  > ```
  """

  defmodule :odcounter_ct do
    @moduledoc false
    def all(_), do: %{}
    def atoi(_, _), do: nil
    def max(_schema), do: 0
  end

  ## Runtime

  @type schema :: atom()

  @type name :: term()

  @type counter :: term()

  @typedoc """
  Options passed to the `init_schema/4` function.

  * `ignore_if_exists` (`t:boolean/0`) — Function won't raise and will do nothing if schema is initialized.
  * `runtime_size` (`t:non_neg_integer/0`) — A maximum amount of counters which are added at runtime to be supported.
  Setting this value to `0` essentially disables the runtime counters
  """
  @type init_schema_option :: {:runtime_size, non_neg_integer()}
    | {:ignore_if_exists, boolean()}

  @doc """
  Initializes the counters.

  ## Example

      iex> ODCounter.init_schema(MySuperCounter)
      iex> ODCounter.new(MySuperCounter, "counter one")
      iex> ODCounter.get(MySuperCounter, "counter one", :key)
      0

  * Every value of the counter is initialized to 0 by default
  * If the counter was initialized before, this function will fail with `ArgumentError`

  Refer to `t:init_schema_option/0` for information about `opts`
  """
  @spec init_schema(schema(), [init_schema_option()]) :: :ok
  def init_schema(schema, opts \\ []) do
    with(
      {_, _} <- :persistent_term.get({__MODULE__.Schema, schema}, []),
      false <- Keyword.get(opts, :ignore_if_exists, false)
    ) do
      raise ArgumentError, "ODCounter #{inspect(schema)} is already initialized"
    end

    runtime_size = Keyword.get(opts, :runtime_size, 1024)

    index_atomics_ref = :atomics.new(1, [])
    :atomics.add(index_atomics_ref, 1, :odcounter_ct.max(schema) + 1)

    :persistent_term.put({__MODULE__.Schema, schema}, {index_atomics_ref, runtime_size})
    :ok
  end

  @typedoc """
  Options passed to the `new/3` function.

  * `counters` (`t:list/0`) — A list of options passed to `:counters.new/2`.
  * `ignore_if_exists` (`t:boolean/0`) — Function won't overwrite and will do nothing if array with this name is initialized.
  """
  @type new_option() :: {:counters, list()}
  | {:ignore_if_exists, boolean()}

  @doc """
  Creates a new counters array of given schema. Creates or updates a `:persistent_term` entry.

  ## Example

     iex> ODCounter.init_schema(:luggage)
     iex> ODCounter.new(:luggage, 1)

  Refer to `t:new_option/0` for information about `opts`
  """
  @spec new(schema(), name(), [new_option()]) :: name
  when name: name()
  def new(schema, name, opts \\ []) do
    counters_opts = Keyword.get(opts, :counters, [])
    {_index_atomics_ref, runtime_size} = :persistent_term.get({__MODULE__.Schema, schema})

    case :persistent_term.get({__MODULE__.State, schema, name}, nil) do
      nil ->
        counters_ref = :counters.new(:odcounter_ct.max(schema) + runtime_size, counters_opts)
        :persistent_term.put({__MODULE__.State, schema, name}, counters_ref)

      _counters_ref ->
        unless Keyword.get(opts, :ignore_if_exists, false) do
          counters_ref = :counters.new(:odcounter_ct.max(schema) + runtime_size, counters_opts)
          :persistent_term.put({__MODULE__.State, schema, name}, counters_ref)
        end
    end

    name
  end

  @doc """
  Deletes an array of counters, removing an entry in `:persistent_term`

  ## Example

     iex> ODCounter.init_schema(ProgrammingLanguagesUsed)
     iex> ODCounter.new(ProgrammingLanguagesUsed, :in_my_project)
     iex> ODCounter.add(ProgrammingLanguagesUsed, :in_my_project, Elixir)
     iex> ODCounter.delete(ProgrammingLanguagesUsed, :in_my_project)
  """
  @spec delete(schema(), name()) :: :ok
  def delete(schema, name) do
    :persistent_term.erase({__MODULE__.State, schema, name})
    :ok
  end

  @doc """
  Removes the counter and all runtime keys

  ## Example

      iex> ODCounter.init_schema(:sheeps)
      iex> ODCounter.new(:sheeps, :in_dream)
      iex> ODCounter.add(:sheeps, :in_dream, :jumped_over_the_fence, 1)
      iex> ODCounter.get(:sheeps, :in_dream, :jumped_over_the_fence)
      1
      iex> ODCounter.remove_schema(:sheeps)
      iex> ODCounter.get(:sheeps, :in_dream, :jumped_over_the_fence)
      ** (ArgumentError) errors were found at the given arguments:
      ...
  """
  @spec remove_schema(schema()) :: :ok
  def remove_schema(schema) do
    :persistent_term.erase({__MODULE__.Schema, schema})

    for kv <- :persistent_term.get() do
      case kv do
        {{:odcounter, ^schema, _} = key, _} ->
          :persistent_term.erase(key)

        {{__MODULE__.State, ^schema, _} = key, _} ->
          :persistent_term.erase(key)

        _ ->
          []
      end
    end

    :ok
  end

  @doc """
  Resets all counters in the schemaspace to 0 (or `to`)

  ## Example

      iex> ODCounter.init_schema(:errors)
      iex> ODCounter.new(:errors, :user_1)
      iex> ODCounter.add(:errors, :user_1, 400)
      iex> ODCounter.add(:errors, :user_1, 500, 5)
      iex> ODCounter.reset(:errors, :user_1)
      iex> ODCounter.to_map(:errors, :user_1)
      %{}
  """
  @spec reset(schema(), name(), integer()) :: :ok
  def reset(schema, name, to \\ 0) do
    {index_atomics_ref, _} = :persistent_term.get({__MODULE__.Schema, schema})
    counters_ref = :persistent_term.get({__MODULE__.State, schema, name})
    max = :atomics.get(index_atomics_ref, 1)

    for i <- 1..max//1 do
      :counters.put(counters_ref, i, to)
    end

    :ok
  end

  @doc """
  Returns values of all counters in a map. Counters with 0 value
  or unitialized counters are not returned.

  ## Example

      iex> ODCounter.init_schema(:requests)
      iex> ODCounter.new(:requests, "service-1")
      iex> ODCounter.add(:requests, "service-1", 200)
      iex> ODCounter.add(:requests, "service-1", 400, 5)
      iex> ODCounter.to_map(:requests, "service-1")
      %{200 => 1, 400 => 5}
  """
  @spec to_map(schema(), name()) :: %{counter() => integer()}
  def to_map(schema, name) do
    counters_ref = :persistent_term.get({__MODULE__.State, schema, name})

    map =
      Map.new(:odcounter_ct.all(schema), fn {counter, index} ->
        {counter, :counters.get(counters_ref, index)}
      end)

    map =
      for {{:odcounter, ^schema, counter}, index} <- :persistent_term.get(), into: map do
        {counter, :counters.get(counters_ref, index)}
      end

    Map.reject(map, & match?({_, 0}, &1))
  end

  @type info :: %{
    counters_info: %{size: non_neg_integer(), memory: non_neg_integer()},
    current_max_index: pos_integer(),
    compile_time_indexes: %{counter() => pos_integer()},
    runtime_indexes: %{counter() => pos_integer()}
  }

  @doc """
  Returns information which can be used for debugging the ODCounter behaviour
  """
  @spec info(schema(), name()) :: info()
  def info(schema, name) do
    {index_atomics_ref, _} = :persistent_term.get({__MODULE__.Schema, schema})
    counters_ref = :persistent_term.get({__MODULE__.State, schema, name})
    max = :atomics.get(index_atomics_ref, 1)

    runtime_indexes =
      for {{:odcounter, ^schema, counter}, index} <- :persistent_term.get(), into: %{} do
        {counter, index}
      end

    %{
      counters_info: :counters.info(counters_ref),
      current_max_index: max,
      compile_time_indexes: :odcounter_ct.all(schema),
      runtime_indexes: runtime_indexes
    }
  end

  @doc """
  Returns a counters reference

  ## Example

      iex> ODCounter.init_schema(:cats)
      iex> ODCounter.new(:cats, {:in_house, "userID:12345"})
      iex> ODCounter.add(:cats, {:in_house, "userID:12345"}, :tuxedo, 2)
      iex> counters = ODCounter.counters(:cats, {:in_house, "userID:12345"})
      iex> :counters.info(counters).size
      1025
  """
  @spec counters(schema(), name()) :: :counters.counters_ref()
  def counters(schema, name) do
    :persistent_term.get({__MODULE__.State, schema, name})
  end

  @doc false
  def do_add(schema, name, index, amount) do
    counters_ref = :persistent_term.get({__MODULE__.State, schema, name})
    :counters.add(counters_ref, index, amount)
    :ok
  end

  @doc false
  def do_put(schema, name, index, value) do
    counters_ref = :persistent_term.get({__MODULE__.State, schema, name})
    :counters.put(counters_ref, index, value)
    :ok
  end

  @doc false
  def do_get(schema, name, index) do
    counters_ref = :persistent_term.get({__MODULE__.State, schema, name})
    :counters.get(counters_ref, index)
  end

  @doc false
  def do_atoi(schema, counter) do
    with nil <- ct_atoi(schema, counter) do
      rt_atoi(schema, counter)
    end
  end

  defp rt_atoi(schema, counter) do
    key = {:odcounter, schema, counter}
    with [] <- :persistent_term.get(key, []) do
      {index_atomics_ref, runtime_size} = :persistent_term.get({__MODULE__.Schema, schema})
      max_size = runtime_size + :odcounter_ct.max(schema)
      new_index = :atomics.add_get(index_atomics_ref, 1, 1)

      if new_index >= max_size do
        :atomics.sub(index_atomics_ref, 1, 1)
        raise "Runtime counters overflow"
      end

      :persistent_term.put(key, new_index)
      new_index
    end
  end

  defp ct_atoi(schema, counter) do
    :odcounter_ct.atoi(schema, counter)
  end

  ## Compile-time

  defp counter_tab_fname do
    Path.join(Mix.Project.build_path(), "odcounter.tab")
  end

  defp init_agent do
    case File.read(counter_tab_fname()) do
      {:ok, encoded_term} -> :erlang.binary_to_term(encoded_term)
      _ -> %{}
    end
  end

  @doc false
  def get_or_start_agent do
    case Agent.start(fn -> init_agent() end, name: __MODULE__.Agent) do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
    end
  end

  defp get_or_create_index(agent, schema, counter) do
    Agent.get_and_update(agent, fn state ->
      case state do
        %{^schema => %{^counter => index}} ->
          {index, state}

        %{^schema => in_schema} ->
          index = map_size(in_schema) + 1
          state = Map.put(state, schema, Map.put(in_schema, counter, index))
          File.write!(counter_tab_fname(), :erlang.term_to_binary(state))
          {index, state}

        state ->
          index = 1
          state = Map.put(state, schema, %{counter => index})
          File.write!(counter_tab_fname(), :erlang.term_to_binary(state))
          {index, state}
      end
    end)
  end

  defp add_or_get_ct_counter(schema, counter) do
    agent = get_or_start_agent()
    get_or_create_index(agent, schema, counter)
  end

  @doc """
  Returns an index of the key

  ## Example

      iex> ODCounter.init_schema(:dogs)
      iex> ODCounter.new(:dogs, {"user_owns", "userID:12345"})
      iex> ODCounter.add(:dogs, {"user_owns", "userID:12345"}, :chiuaua, 42)
      iex> index = ODCounter.atoi(:dogs, :chiuaua)
      iex> :counters.get(ODCounter.counters(:dogs, {"user_owns", "userID:12345"}), index)
      42
  """
  defmacro atoi(schema, counter) do
    schema = Macro.expand(schema, __CALLER__)

    unless is_atom(schema) do
      raise CompileError,
        file: __CALLER__.file,
        line: __CALLER__.line,
        description: "Name must be a compile-time atom. Got #{Code.format_string! Macro.to_string(schema)}"
    end

    counter = Macro.expand(counter, __CALLER__)

    case Macro.quoted_literal?(counter) do
      true ->
        prepared_caller_env = Code.env_for_eval(__CALLER__)
        {counter, [], _} = Code.eval_quoted_with_env(counter, [], prepared_caller_env)

        if __CALLER__.module != nil do
          Module.put_attribute(__CALLER__.module, :before_compile, {__MODULE__, :c_hook})
        end

        index = add_or_get_ct_counter(schema, counter)
        index

      false ->
        quote do
          unquote(__MODULE__).do_atoi(unquote(schema), unquote(counter))
        end
    end
  end

  @doc """
  Increases the value of the `counter`

  ## Example

      iex> ODCounter.init_schema(:things)
      iex> ODCounter.new(:things, :here)
      iex> ODCounter.add(:things, :here, :some_thing) # Default is to add 1
      iex> ODCounter.add(:things, :here, :some_thing, 2)
      iex> ODCounter.get(:things, :here, :some_thing)
      3
  """
  defmacro add(schema, name, counter, amount \\ 1) do
    quote do
      name = unquote(name)
      index = unquote(__MODULE__).atoi(unquote(schema), unquote(counter))
      unquote(__MODULE__).do_add(unquote(schema), name, index, unquote(amount))
      :ok
    end
  end

  @doc """
  Decreases the `counter` value by `amount`. It expands to `add(schema, counter, -amount)`.
  Refer to `add/3` for more information
  """
  defmacro sub(schema, name, counter, amount \\ 1) do
    quote do
      unquote(__MODULE__).add(unquote(schema), unquote(name), unquote(counter), -unquote(amount))
    end
  end

  @doc """
  Sets the `counter` to the `value`

  ## Example

      iex> ODCounter.init_schema(:clock)
      iex> ODCounter.new(:clock, {"user-wristwatch", 1883})
      iex> ODCounter.put(:clock, {"user-wristwatch", 1883}, :hours, 13)
      iex> ODCounter.put(:clock, {"user-wristwatch", 1883}, :minutes, 44)
      iex> ODCounter.put(:clock, {"user-wristwatch", 1883}, :seconds, 59)
      iex> ODCounter.to_map(:clock, {"user-wristwatch", 1883})
      %{hours: 13, minutes: 44, seconds: 59}
  """
  defmacro put(schema, name, counter, value) do
    quote do
      name = unquote(name)
      index = unquote(__MODULE__).atoi(unquote(schema), unquote(counter))
      unquote(__MODULE__).do_put(unquote(schema), name, index, unquote(value))
      :ok
    end
  end

  @doc """
  Gets the value of the counter. If the counter was never set, 0 is returned

  ## Example

      iex> ODCounter.init_schema(:animals)
      iex> ODCounter.new(:animals, :farm)
      iex> ODCounter.add(:animals, :farm, :cows)
      iex> ODCounter.add(:animals, :farm, :cows, 5)
      iex> ODCounter.get(:animals, :farm, :cows)
      6
      iex> ODCounter.get(:animals, :farm, :parrots)
      0
  """
  defmacro get(schema, name, counter) do
    quote do
      name = unquote(name)
      index = unquote(__MODULE__).atoi(unquote(schema), unquote(counter))
      unquote(__MODULE__).do_get(unquote(schema), name, index)
    end
  end

  @doc false
  def c_hook(env) do
    unless Module.get_attribute(env.module, :odcounter_chook_called, false) do
      Module.put_attribute(env.module, :odcounter_chook_called, true)

      change_back? =
        case Code.get_compiler_option(:ignore_module_conflict) do
          true ->
            false

          false ->
            Code.put_compiler_option(:ignore_module_conflict, true)
            true
        end

      try do
        defmodule :odcounter_ct do
          @moduledoc false

          agent = ODCounter.get_or_start_agent()

          @all Agent.get(agent, &Function.identity/1)
          @max Map.new(@all, fn {schema, in_schema} -> {schema, Enum.max(Map.values(in_schema), &>=/2, fn -> 0 end)} end)

          for {schema, in_schema} <- @all do
            @schema schema
            @in_schema in_schema

            def all(@schema), do: @in_schema
          end

          for {schema, in_schema} <- @all, {counter, index} <- in_schema do
            @schema schema
            @counter counter
            @index index

            def atoi(@schema, @counter), do: @index
          end

          def atoi(_, _), do: nil

          def max(schema) do
            Map.get(@max, schema, 0)
          end
        end
      after
        if change_back? do
          Code.put_compiler_option(:ignore_module_conflict, false)
        end
      end
    end
  end
end
