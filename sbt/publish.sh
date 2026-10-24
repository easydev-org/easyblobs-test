#!/bin/sh
# sbt: a real sbt build that resolves through the mirrored Ivy repository.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD with sbt itself; the resolvers point at the mount.
sbt -batch -Dsbt.log.noformat=true compile 2>&1 | tail -5

out=$(find target -name '*.class' | head -1)
[ -n "$out" ] || { echo "sbt: compilation produced no classes" >&2; exit 1; }

# PACKAGE + PUBLISH the compiled output as a jar, then read it back.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
( cd target && zip -qr "$TMP/hello-1.0.0.jar" . )
jar="$TMP/hello-1.0.0.jar"
# sbt's own organisation, so this jar cannot collide with maven's or gradle's.
code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \
  "$EASYBLOBS_BASE/dev/easyblobs/test/sbt/hello/1.0.0/hello-1.0.0.jar" \
  --data-binary "@$jar")
case "$code" in 200|201) ;; *) echo "sbt: upload -> $code" >&2; exit 1 ;; esac
curl -fsS -o /tmp/sbt-back.jar \
  "$EASYBLOBS_BASE/dev/easyblobs/test/sbt/hello/1.0.0/hello-1.0.0.jar"
cmp -s /tmp/sbt-back.jar "$jar" || {
  echo "sbt: the served jar differs" >&2; exit 1; }
echo "sbt: compiled, packaged, published and re-read the jar (bytes verified)"
