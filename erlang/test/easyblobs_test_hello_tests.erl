-module(easyblobs_test_hello_tests).
-include_lib("eunit/include/eunit.hrl").

greet_test() ->
    ?assertEqual("hello easyblobs", easyblobs_test_hello:greet("easyblobs")).
