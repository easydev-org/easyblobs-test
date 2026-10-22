-module(easyblobs_test_hello).
-export([greet/1]).

-spec greet(string()) -> string().
greet(Name) ->
    "hello " ++ Name.
