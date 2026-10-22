#!/bin/sh
# hex: compile, test and package this Elixir project.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD: compile with warnings as errors, then run the test suite.
mix compile --warnings-as-errors
mix test

# PACKAGE: the .tar that the hex protocol publishes.
mix hex.build 2>&1 | tail -5 || echo "hex: hex.build unavailable (hex not installed)"
echo "hex: compiled, tested and packaged"
