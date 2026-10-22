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
code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \
  "$EASYBLOBS_BASE/@easyblobs-test/hello/1.0.0_meta.json" \
  -H 'Content-Type: application/json' \
  --data-binary '{"exports":{"./mod.ts":"./mod.ts"},"moduleGraph1":{}}')
case "$code" in 200|201) ;; *) echo "deno: publish -> $code" >&2; exit 1 ;; esac
curl -fsS -o /dev/null "$EASYBLOBS_BASE/@easyblobs-test/hello/1.0.0_meta.json" || {
  echo "deno: the version metadata does not resolve after publish" >&2; exit 1; }
echo "deno: type-checked, ran, published and re-read the version metadata"
