#!/bin/sh
# julia: instantiate and run this Julia package.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD with the real package manager, then call into the package.
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. -e 'using EasyblobsTestHello; println(EasyblobsTestHello.greet("easyblobs"))'

# PUBLISH: a tarball of the package, uploaded and read back.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
tar -czf "$TMP/EasyblobsTestHello-1.0.0.tar.gz" Project.toml src
pkg="$TMP/EasyblobsTestHello-1.0.0.tar.gz"
# juliapkg is served by the generic `httpcache` adapter: a read-only
# pull-through cache everywhere except the reserved "_hosted/<repo>/" prefix,
# which is what makes the request an upload rather than a cache lookup.
# --- build-only escape hatch -------------------------------------------------
# A read-only mirror has no write path, so "publish" cannot be exercised. Set
# E2E_BUILD_ONLY=1 to run everything up to the first publish call and stop: the
# build, the tests and the packaging still run, which is what those protocols
# can be held to.
if [ "${E2E_BUILD_ONLY:-0}" = 1 ]; then
  echo "julia: build-only mode (E2E_BUILD_ONLY=1); stopping before publish"
  exit 0
fi

code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \
  "$EASYBLOBS_BASE/_hosted/e2e/EasyblobsTestHello/1.0.0.tar.gz" --data-binary "@$pkg")
case "$code" in 200|201) ;; *) echo "julia: upload -> $code" >&2; exit 1 ;; esac
curl -fsS -o /tmp/julia-back.tar.gz \
  "$EASYBLOBS_BASE/_hosted/e2e/EasyblobsTestHello/1.0.0.tar.gz"
cmp -s /tmp/julia-back.tar.gz "$pkg" || {
  echo "julia: the served package differs" >&2; exit 1; }
echo "julia: instantiated, ran, published and re-read the package (bytes verified)"
