defmodule EasyblobsTestHelloTest do
  use ExUnit.Case, async: true

  test "greets" do
    assert EasyblobsTestHello.greet("easyblobs") == "hello easyblobs"
  end
end
