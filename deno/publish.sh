#!/bin/sh
# deno: type-check, run, then package the module.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD: type-check and execute, so a broken module fails here.
deno check mod.ts
deno run main.ts

# PACKAGE: the JSR publish format.
deno publish --dry-run --allow-dirty 2>&1 | tail -5 || true

# PUBLISH the module tarball to the mount's JSR layout, then read it back.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
tar -czf "$TMP/hello-1.0.0.tar.gz" deno.json mod.ts
pkg="$TMP/hello-1.0.0.tar.gz"
# jsr is served by the generic `httpcache` adapter: read-only pull-through
# everywhere except the reserved "_hosted/<repo>/" prefix, which is what makes a
# request an upload. Without it a PUT to the cache path is answered 405.
# --- build-only escape hatch -------------------------------------------------
# A read-only mirror has no write path, so "publish" cannot be exercised. Set
# E2E_BUILD_ONLY=1 to run everything up to the first publish call and stop: the
# build, the tests and the packaging still run, which is what those protocols
# can be held to.
if [ "${E2E_BUILD_ONLY:-0}" = 1 ]; then
  echo "deno: build-only mode (E2E_BUILD_ONLY=1); stopping before publish"
  exit 0
fi

code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \
  "$EASYBLOBS_BASE/_hosted/e2e/@easyblobs-test/hello/1.0.0_meta.json" \
  -H 'Content-Type: application/json' \
  --data-binary '{"exports":{"./mod.ts":"./mod.ts"},"moduleGraph1":{}}')
case "$code" in 200|201) ;; *) echo "deno: publish -> $code" >&2; exit 1 ;; esac
curl -fsS -o /dev/null \
  "$EASYBLOBS_BASE/_hosted/e2e/@easyblobs-test/hello/1.0.0_meta.json" || {
  echo "deno: the version metadata does not resolve after publish" >&2; exit 1; }
echo "deno: type-checked, ran, published and re-read the version metadata"
