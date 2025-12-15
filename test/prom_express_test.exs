defmodule PromExpressTest do
  use ExUnit.Case
  doctest PromExpress

  test "greets the world" do
    assert PromExpress.hello() == :world
  end
end
