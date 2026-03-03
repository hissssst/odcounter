# ODCounter

A `:counters`, but with namespaces and terms as names

## Usage

```elixir
iex> ODCounter.init_schema(Metrics)
iex> ODCounter.new(Metrics, :my_app)
iex> ODCounter.add(Metrics, :my_app, :requests, 5)
iex> ODCounter.get(Metrics, :my_app, :requests)
5
iex> ODCounter.add(Metrics, :my_app, :succeeded_requests, 4)
iex> ODCounter.add(Metrics, :my_app, :failed_requests, 1)
iex> ODCounter.to_map(Metrics, :my_app)
%{requests: 5, succeeded_requests: 4, failed_requests: 1}
```

## Features

* Use `:counters`, but with arbitrary terms instead of indexes. No more
  initialization ceremony with passing the reference around, maintaining
  term-to-index associations. Just init the counter and pass terms as keys

* 0-cost abstractions which provide maximum efficiency.
  If you pass key term as literal, it will be translated to the array index at compile-time.
  If key term is unknown at compile time, ODCounter will utilize runtime storage for associations.

* Built-in namespaces allow separate initialization and utilization of the counters in different parts of
  project. Whether it is dependency or your domains, there will be no clashes

## Installation

```elixir
def deps do
  [
    {:odcounter, "~> 2.0"}
  ]
end
```
