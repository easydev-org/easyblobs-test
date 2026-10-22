#!/bin/sh
# erlang: compile with rebar3 and run the eunit suite.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD + TEST with the real build tool.
rebar3 compile 2>&1 | tail -5
rebar3 eunit 2>&1 | tail -8

beam=$(find _build -name 'easyblobs_test_hello.beam' | head -1)
[ -n "$beam" ] || { echo "erlang: no beam file produced" >&2; exit 1; }
echo "erlang: compiled and tested $beam"
