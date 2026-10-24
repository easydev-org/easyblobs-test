#!/bin/sh
# rubygems: build the gem, load it, publish it, read it back.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD: gem build validates the gemspec and produces a real .gem.
gem build easyblobs_test_hello.gemspec >/dev/null
gemfile=$(ls easyblobs_test_hello-*.gem | head -1)
ruby test_gem.rb

# PUBLISH whatever gem produced.
# --- build-only escape hatch -------------------------------------------------
# A read-only mirror has no write path, so "publish" cannot be exercised. Set
# E2E_BUILD_ONLY=1 to run everything up to the first publish call and stop: the
# build, the tests and the packaging still run, which is what those protocols
# can be held to.
if [ "${E2E_BUILD_ONLY:-0}" = 1 ]; then
  echo "ruby: build-only mode (E2E_BUILD_ONLY=1); stopping before publish"
  exit 0
fi

gem push --host "$EASYBLOBS_BASE" "$gemfile" || {
  echo "rubygems: gem push failed" >&2; exit 1; }

# READ BACK: the versions API must list the release.
curl -fsS "$EASYBLOBS_BASE/api/v1/versions/easyblobs_test_hello.json" \
  | grep -q '"1.0.0"' || {
    echo "rubygems: the versions API does not list 1.0.0" >&2; exit 1; }
echo "rubygems: built, loaded and published $gemfile"
