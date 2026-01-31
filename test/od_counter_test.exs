defmodule ODCounterTest do
  use ExUnit.Case
  if Version.match?(System.version(), "~> 1.19") do
    doctest ODCounter
  else
    doctest ODCounter, except: [remove: 1]
  end
end
