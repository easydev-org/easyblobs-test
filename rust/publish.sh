#!/bin/sh
# cargo: build, test, package and publish this crate.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD + TEST, so a broken toolchain or crate fails here.
# easysetup publishes cargo as its OWN setup ('cargo'), separate from 'rust'
# (which is pkgs.rustc). A rustc-only closure has the compiler but no cargo, so
# this fixture needs both setups listed; if only 'rust' was installed, say so
# precisely rather than letting 'cargo: not found' stand in for a packaging fact.
if ! command -v cargo >/dev/null 2>&1; then
  echo "cargo: no cargo on PATH. easysetup publishes it as the separate setup" >&2
  echo "cargo: 'cargo' (pkgs.cargo); 'rust' alone is rustc-only so it cannot" >&2
  echo "cargo: build or publish a crate. rustc is: $(command -v rustc || echo missing)" >&2
  exit 1
fi
echo "cargo: using $(command -v cargo) ($(cargo --version 2>&1 | head -1))"
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
