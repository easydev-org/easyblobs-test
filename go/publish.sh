#!/bin/sh
# go: build, test and publish this module as a module zip.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD + TEST, so a broken toolchain or module fails here.
go build ./...
go test ./...
go run ./cmd/app

# PUBLISH. The adapter serves .mod by extracting go.mod from the stored zip, so
# the module must be uploaded as the canonical zip - a plain text body would
# produce a module the go toolchain cannot consume.
MOD="example.com/easyblobs-test/hello"
VER="v1.0.0"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/zip/$MOD@$VER"
cp go.mod hello.go "$TMP/zip/$MOD@$VER/"
( cd "$TMP/zip" && zip -qr "$TMP/mod.zip" . )

code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \
  "$EASYBLOBS_BASE/upload?name=$MOD&version=$VER" \
  -H 'Content-Type: application/octet-stream' --data-binary "@$TMP/mod.zip")
case "$code" in 200|201) ;; *) echo "go: upload -> $code" >&2; exit 1 ;; esac

# READ BACK: the served go.mod must be the one shipped, not a phantom.
curl -fsS "$EASYBLOBS_BASE/$MOD/@v/$VER.mod" | grep -q "module $MOD" || {
  echo "go: served go.mod does not declare the module path" >&2; exit 1; }
curl -fsS -o /dev/null "$EASYBLOBS_BASE/$MOD/@v/$VER.info" || {
  echo "go: no .info" >&2; exit 1; }
echo "go: published and re-read $MOD@$VER"
