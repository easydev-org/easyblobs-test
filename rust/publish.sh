#!/bin/sh
# cargo: build, test, package and publish this crate.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD + TEST, so a broken toolchain or crate fails here.
cargo build --quiet
cargo test --quiet

# PACKAGE: `cargo package` produces the .crate a registry stores, and it also
# validates the manifest - which is the part that catches a bad Cargo.toml.
cargo package --no-verify --allow-dirty 2>&1 | tail -3
CRATE=$(ls target/package/easyblobs-test-hello-1.0.0.crate)
[ -s "$CRATE" ] || { echo "cargo: no .crate produced" >&2; exit 1; }

# PUBLISH.
#
# /api/v1/crates/new takes cargo's own binary body (name, version, JSON, crate
# bytes, concatenated with lengths). The adapter accepts the name and version as
# QUERY PARAMETERS, which is both documented in its publish handler and far more
# legible here - so the body can be the .crate itself.
code=$(curl -sS -o /tmp/cargo-resp.json -w '%{http_code}' -X PUT \
  "$EASYBLOBS_BASE/api/v1/crates/new?name=easyblobs-test-hello&version=1.0.0" \
  -H 'Content-Type: application/octet-stream' --data-binary "@$CRATE")
case "$code" in 200|201) ;; *) echo "cargo: publish -> $code" >&2; cat /tmp/cargo-resp.json >&2; exit 1 ;; esac

# READ BACK: the crate must be downloadable and byte-identical. A registry that
# answers 201 and then serves different bytes is broken in a way status codes
# hide.
curl -fsS -o /tmp/cargo-back.crate \
  "$EASYBLOBS_BASE/api/v1/crates/easyblobs-test-hello/1.0.0/download"
cmp -s /tmp/cargo-back.crate "$CRATE" || {
  echo "cargo: the served .crate differs from the built one" >&2; exit 1; }
echo "cargo: built, tested, published and re-read easyblobs-test-hello 1.0.0 (bytes verified)"
