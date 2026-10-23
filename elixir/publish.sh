#!/bin/sh
# hex: compile, test and package this Elixir project.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD: compile with warnings as errors, then run the test suite.
mix compile --warnings-as-errors
mix test

# PACKAGE: the .tar that the hex protocol publishes.
#
# hex is not part of a bare Elixir install. Without it `mix hex.build` produces
# nothing - and the fixture then reports "produced no package", which reads as
# "the fixture cannot package" rather than "hex was missing".
mix local.hex --force >/dev/null 2>&1 || mix local.hex --force --if-missing >/dev/null 2>&1 || true
mix hex.build 2>&1 | tail -5

# PUBLISH. The hex adapter serves POST /publish with name and version as QUERY
# parameters; a bare PUT to a path is not one of its routes.
pkg=$(ls easyblobs_test_hello-*.tar | head -1)
[ -n "$pkg" ] || { echo "hex: mix hex.build produced no package (is hex installed?)" >&2; exit 1; }
code=$(curl -sS -o /tmp/hex-resp.json -w '%{http_code}' -X POST \
  "$EASYBLOBS_BASE/publish?name=easyblobs_test_hello&version=1.0.0" \
  -H 'Content-Type: application/octet-stream' --data-binary "@$pkg")
case "$code" in 200|201) ;; *) echo "hex: publish -> $code" >&2; cat /tmp/hex-resp.json >&2; exit 1 ;; esac

# READ BACK: the release must be retrievable and byte-identical.
curl -fsS -o /tmp/hex-back.tar \
  "$EASYBLOBS_BASE/packages/easyblobs_test_hello/releases/1.0.0"
cmp -s /tmp/hex-back.tar "$pkg" || {
  echo "hex: the served package differs from the built one" >&2; exit 1; }
echo "hex: compiled, tested, published and re-read $pkg (bytes verified)"
