#!/bin/sh
# hex: compile, test and package this Elixir project.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD: compile with warnings as errors, then run the test suite.
mix compile --warnings-as-errors
mix test

# PACKAGE: the .tar that the hex protocol publishes.
mix hex.build 2>&1 | tail -5 || echo "hex: hex.build unavailable (hex not installed)"

# PUBLISH the package tarball to the mount, then read it back.
pkg=$(ls easyblobs_test_hello-*.tar | head -1)
[ -n "$pkg" ] || { echo "hex: mix hex.build produced no package" >&2; exit 1; }
code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \
  "$EASYBLOBS_BASE/hex/$pkg" --data-binary "@$pkg")
case "$code" in 200|201) ;; *) echo "hex: upload -> $code" >&2; exit 1 ;; esac
curl -fsS -o "/tmp/hex-back-$pkg" "$EASYBLOBS_BASE/hex/$pkg"
cmp -s "/tmp/hex-back-$pkg" "$pkg" || {
  echo "hex: the served package differs from the built one" >&2; exit 1; }
echo "hex: compiled, tested, published and re-read $pkg (bytes verified)"
