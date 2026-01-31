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

  It is possible to disable the runtime fallback by setting the `runtime_size` option of `init/2` to 0.
  See `t:init_option/0` for more information

  > #### Warning {: .warning}
  >
  > Any term passed as the counter key will be added to `persistent_term`, and therefore it won't be
  > garbage collected automatically. In order to clear associations table, you must call `remove/1`
  >
  > **Example:**
  > ```
  > very_large_list = Enum.to_list(1..1000)
  > ODCounter.init(:structures)
  > ODCounter.get(:structures, very_large_list) # very_large_list won't be garbage collected now
  > ```

  > #### Tip {: .tip}
  >
  > In order to achieve maximum efficieny, you should pass keys as literals,
  > not variables or function calls
  >
  > **Example:**
  > ```
  > ODCounter.init(:letters)
  > ODCounter.add(:letters, :a) # fast
  > b = :b
  > ODCounter.add(:letters, b) # slow
  > ```
  """

  defmodule :odcounter_ct do
    @moduledoc false
    def all(_), do: %{}
    def atoi(_, _), do: nil
    def max(_name), do: 0
  end

  ## Runtime

  @type name :: atom()

  @type counter :: any()

  @typedoc """
  Options passed to the `init/4` function.

  * `counters` (`t:counters.init/0`) — A list of options passed to `:counters.new/2`.
  * `runtime_size` (`t:non_neg_integer/0`) — A maximum amount of counters which are added at runtime to be supported.
  Setting this value to `0` essentially disables the runtime counters
  """
  @type init_option :: {:counters, list()}
    | {:runtime_size, non_neg_integer()}

  @doc """
  Initializes the counters.

  ## Example

      iex> ODCounter.init(MySuperCounter)
      iex> ODCounter.get(MySuperCounter, :key)
      0

  * Every value of the counter is initialized to 0 by default
  * If the counter was initialized before, this function will fail with `ArgumentError`

  Refer to `t:init_option/0` for information about `opts`
  """
  @spec init(name(), [init_option()]) :: :ok
  def init(name, opts \\ []) do
    with {_, _} <- :persistent_term.put({__MODULE__, name}, []) do
      raise ArgumentError, "ODCounter #{inspect(name)} is already initialized"
    end
    counters_opts = Keyword.get(opts, :counters, [])
    runtime_size = Keyword.get(opts, :runtime_size, 1024)

    counters_ref = :counters.new(:odcounter_ct.max(name) + runtime_size, counters_opts)

    index_atomics_ref = :atomics.new(1, [])
    :atomics.add(index_atomics_ref, 1, :odcounter_ct.max(name) + 1)

    :persistent_term.put({__MODULE__, name}, {counters_ref, index_atomics_ref})
    :ok
  end

  @doc """
  Removes the counter and all runtime keys

  ## Example

      iex> ODCounter.init(:sheeps)
      iex> ODCounter.add(:sheeps, :jumped_over_the_fence, 1)
      iex> ODCounter.get(:sheeps, :jumped_over_the_fence)
      1
      iex> ODCounter.remove(:sheeps)
      iex> ODCounter.get(:sheeps, :jumped_over_the_fence)
      ** (ArgumentError) errors were found at the given arguments:
      ...
  """
  @spec remove(name()) :: :ok
  def remove(name) do
    :persistent_term.erase({__MODULE__, name})
    for {{:odcounter, ^name, _counter} = key, _index} <- :persistent_term.get() do
      :persistent_term.erase(key)
    end
    :ok
  end

  @doc """
  Resets all counters in the namespace to 0 (or `to`)

  ## Example

      iex> ODCounter.init(:errors)
      iex> ODCounter.add(:errors, 400)
      iex> ODCounter.add(:errors, 500, 5)
      iex> ODCounter.reset(:errors)
      iex> ODCounter.to_map(:errors)
      %{}
  """
  @spec reset(name()) :: :ok
  def reset(name, to \\ 0) do
    {counters_ref, index_atomics_ref} = :persistent_term.get({__MODULE__, name})
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

      iex> ODCounter.init(:requests)
      iex> ODCounter.add(:requests, 200)
      iex> ODCounter.add(:requests, 400, 5)
      iex> ODCounter.to_map(:requests)
      %{200 => 1, 400 => 5}
  """
  @spec to_map(name()) :: %{counter() => integer()}
  def to_map(name) do
    {counters_ref, _} = :persistent_term.get({__MODULE__, name})

    map =
      Map.new(:odcounter_ct.all(name), fn {counter, index} ->
        {counter, :counters.get(counters_ref, index)}
      end)

    map =
      for {{:odcounter, ^name, counter}, index} <- :persistent_term.get(), into: map do
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
  @spec info(name()) :: info()
  def info(name) do
    {counters_ref, index_atomics_ref} = :persistent_term.get({__MODULE__, name})
    max = :atomics.get(index_atomics_ref, 1)

    runtime_indexes =
      for {{:odcounter, ^name, counter}, index} <- :persistent_term.get(), into: %{} do
        {counter, index}
      end

    %{
      counters_info: :counters.info(counters_ref),
      current_max_index: max,
      compile_time_indexes: :odcounter_ct.all(name),
      runtime_indexes: runtime_indexes
    }
  end

  @doc """
  Returns a counters reference

  ## Example

      iex> ODCounter.init(:cats)
      iex> ODCounter.add(:cats, :tuxedo, 2)
      iex> counters = ODCounter.counters(:dogs)
      iex> :counters.info(counters).size
      1025
  """
  @spec counters(name()) :: :counters.counters_ref()
  def counters(name) do
    {counters_ref, _index_atomics_ref} = :persistent_term.get({__MODULE__, name})
    counters_ref
  end

  @doc false
  def do_add(name, index, amount) do
    {counters_ref, _} = :persistent_term.get({__MODULE__, name})
    :counters.add(counters_ref, index, amount)
    :ok
  end

  @doc false
  def do_put(name, index, value) do
    {counters_ref, _} = :persistent_term.get({__MODULE__, name})
    :counters.put(counters_ref, index, value)
    :ok
  end

  @doc false
  def do_get(name, index) do
    {counters_ref, _} = :persistent_term.get({__MODULE__, name})
    :counters.get(counters_ref, index)
  end

  @doc false
  def do_atoi(name, counter) do
    with nil <- ct_atoi(name, counter) do
      rt_atoi(name, counter)
    end
  end

  defp rt_atoi(name, counter) do
    key = {:odcounter, name, counter}
    with [] <- :persistent_term.get(key, []) do
      {counters_ref, index_atomics_ref} = :persistent_term.get({__MODULE__, name})
      new_index = :atomics.add_get(index_atomics_ref, 1, 1)

      if new_index >= :counters.info(counters_ref).size do
        :atomics.sub(index_atomics_ref, 1, 1)
        raise "Runtime counters overflow"
      end

      :persistent_term.put(key, new_index)
      new_index
    end
  end

  defp ct_atoi(name, counter) do
    :odcounter_ct.atoi(name, counter)
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

  defp get_or_create_index(agent, name, counter) do
    Agent.get_and_update(agent, fn state ->
      case state do
        %{^name => %{^counter => index}} ->
          {index, state}

        %{^name => in_name} ->
          index = map_size(in_name) + 1
          state = Map.put(state, name, Map.put(in_name, counter, index))
          File.write!(counter_tab_fname(), :erlang.term_to_binary(state))
          {index, state}

        state ->
          index = 1
          state = Map.put(state, name, %{counter => index})
          File.write!(counter_tab_fname(), :erlang.term_to_binary(state))
          {index, state}
      end
    end)
  end

  defp add_or_get_ct_counter(name, counter) do
    agent = get_or_start_agent()
    get_or_create_index(agent, name, counter)
  end

  @doc """
  Returns an index of the key

  ## Example

      iex> ODCounter.init(:dogs)
      iex> ODCounter.add(:dogs, :chiuaua, 42)
      iex> index = ODCounter.atoi(:dogs, :chiuaua)
      iex> :counters.get(ODCounter.counters(:dogs), index)
      42
  """
  defmacro atoi(name, counter) do
    name = Macro.expand(name, __CALLER__)

    unless is_atom(name) do
      raise CompileError,
        file: __CALLER__.file,
        line: __CALLER__.line,
        description: "Name must be a compile-time atom. Got #{Code.format_string! Macro.to_string(name)}"
    end

    counter = Macro.expand(counter, __CALLER__)

    case Macro.quoted_literal?(counter) do
      true ->
        prepared_caller_env = Code.env_for_eval(__CALLER__)
        {counter, [], _} = Code.eval_quoted_with_env(counter, [], prepared_caller_env)

        if __CALLER__.module != nil do
          Module.put_attribute(__CALLER__.module, :after_compile, {__MODULE__, :c_hook})
        end

        index = add_or_get_ct_counter(name, counter)
        index

      false ->
        quote do
          unquote(__MODULE__).do_atoi(unquote(name), unquote(counter))
        end
    end
  end

  @doc """
  Increases the value of the `counter`

  ## Example

      iex> ODCounter.init(:things)
      iex> ODCounter.add(:things, :some_thing) # Default is to add 1
      iex> ODCounter.add(:things, :some_thing, 2)
      iex> ODCounter.get(:things, :some_thing)
      3
  """
  defmacro add(name, counter, amount \\ 1) do
    quote do
      index = unquote(__MODULE__).atoi(unquote(name), unquote(counter))
      unquote(__MODULE__).do_add(unquote(name), index, unquote(amount))
      :ok
    end
  end

  @doc """
  Decreases the `counter` value by `amount`. It expands to `add(name, counter, -amount)`.
  Refer to `add/3` for more information
  """
  defmacro sub(name, counter, amount \\ 1) do
    quote do
      unquote(__MODULE__).add(unquote(name), unquote(counter), -unquote(amount))
    end
  end

  @doc """
  Sets the `counter` to the `value`

  ## Example

      iex> ODCounter.init(:clock)
      iex> ODCounter.put(:clock, :hours, 13)
      iex> ODCounter.put(:clock, :minutes, 44)
      iex> ODCounter.put(:clock, :seconds, 59)
      iex> ODCounter.to_map(:clock)
      %{hours: 13, minutes: 44, seconds: 59}
  """
  defmacro put(name, counter, value) do
    quote do
      index = unquote(__MODULE__).atoi(unquote(name), unquote(counter))
      unquote(__MODULE__).do_put(unquote(name), index, unquote(value))
      :ok
    end
  end

  @doc """
  Gets the value of the counter. If the counter was never set, 0 is returned

  ## Example

      iex> ODCounter.init(:animals)
      iex> ODCounter.add(:animals, :cows)
      iex> ODCounter.add(:animals, :cows, 5)
      iex> ODCounter.get(:animals, :cows)
      6
      iex> ODCounter.get(:animals, :parrots)
      0
  """
  defmacro get(name, counter) do
    quote do
      index = unquote(__MODULE__).atoi(unquote(name), unquote(counter))
      unquote(__MODULE__).do_get(unquote(name), index)
    end
  end

  @doc false
  def c_hook(_env, _bytecode) do
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
        @max Map.new(@all, fn {name, in_name} -> {name, Enum.max(Map.values(in_name), &>=/2, fn -> 0 end)} end)

        # IO.inspect @all, label: :generating

        for {name, in_name} <- @all do
          @name name
          @in_name in_name

          def all(@name), do: @in_name
        end

        for {name, in_name} <- @all, {counter, index} <- in_name do
          @name name
          @counter counter
          @index index

          def atoi(@name, @counter), do: @index
        end

        def atoi(_, _), do: nil

        def max(name) do
          Map.get(@max, name, 0)
        end
      end
    after
      if change_back? do
        Code.put_compiler_option(:ignore_module_conflict, false)
      end
    end
  end
end
