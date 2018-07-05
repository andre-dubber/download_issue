defmodule IssuesDemoTest do
  use ExUnit.Case
  doctest IssuesDemo

  test "greets the world" do
    assert IssuesDemo.hello() == :world
  end
end
