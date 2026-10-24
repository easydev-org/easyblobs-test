#!/bin/sh
# erlang: compile with rebar3 and run the eunit suite.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD + TEST with the real build tool.
rebar3 compile 2>&1 | tail -5
rebar3 eunit 2>&1 | tail -8

beam=$(find _build -name 'easyblobs_test_hello.beam' | head -1)
[ -n "$beam" ] || { echo "erlang: no beam file produced" >&2; exit 1; }

# PACKAGE + PUBLISH: assemble an archive of the application and push it.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
tar -czf "$TMP/easyblobs_test_hello-1.0.0.tar.gz" src
pkg="$TMP/easyblobs_test_hello-1.0.0.tar.gz"
# --- build-only escape hatch -------------------------------------------------
# A read-only mirror has no write path, so "publish" cannot be exercised. Set
# E2E_BUILD_ONLY=1 to run everything up to the first publish call and stop: the
# build, the tests and the packaging still run, which is what those protocols
# can be held to.
if [ "${E2E_BUILD_ONLY:-0}" = 1 ]; then
  echo "erlang: build-only mode (E2E_BUILD_ONLY=1); stopping before publish"
  exit 0
fi

code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \
  "$EASYBLOBS_BASE/hex/easyblobs_test_hello-1.0.0.tar.gz" --data-binary "@$pkg")
case "$code" in 200|201) ;; *) echo "erlang: upload -> $code" >&2; exit 1 ;; esac
curl -fsS -o /tmp/erlang-back.tar.gz \
  "$EASYBLOBS_BASE/hex/easyblobs_test_hello-1.0.0.tar.gz"
cmp -s /tmp/erlang-back.tar.gz "$pkg" || {
  echo "erlang: the served archive differs" >&2; exit 1; }
echo "erlang: compiled, tested, published and re-read the release (bytes verified)"
