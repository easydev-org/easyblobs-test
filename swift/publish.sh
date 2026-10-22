#!/bin/sh
# swift: build and test a real SwiftPM package.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD + TEST with SwiftPM, so the compiler and the test runner both run.
swift build 2>&1 | tail -5
swift test 2>&1 | tail -8

# PUBLISH the source archive to the SwiftPM registry, then read it back.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# The registry path is /{scope}/{name}/{version} - THREE segments. A dotted
# single identifier is rejected with "invalid upload path" (400).
scope=easyblobs-test
name=hello
id="$scope.$name"
mkdir -p "$TMP/pkg"
cp -a Package.swift Sources "$TMP/pkg/"
( cd "$TMP/pkg" && zip -qr "$TMP/$id-1.0.0.zip" . )
zipf="$TMP/$id-1.0.0.zip"
code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \
  "$EASYBLOBS_BASE/$scope/$name/1.0.0" --data-binary "@$zipf")
case "$code" in 200|201) ;; *) echo "swift: upload -> $code" >&2; exit 1 ;; esac
curl -fsS -o /dev/null "$EASYBLOBS_BASE/$scope/$name/1.0.0" || {
  echo "swift: the release does not resolve after upload" >&2; exit 1; }
echo "swift: built, tested, published and re-read the release"
