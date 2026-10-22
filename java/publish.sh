#!/bin/sh
# maven: compile, run the jar, then publish it to the mount and read it back.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD: compiles the sources and produces target/hello-1.0.0.jar.
mvn -B -q package
jar=$(ls target/hello-*.jar | head -1)
[ -s "$jar" ] || { echo "maven: no jar produced" >&2; exit 1; }

# RUN it, so a broken class fails here rather than in production.
java -cp "$jar" dev.easyblobs.test.hello.Main

# PUBLISH the jar through the mount.
code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \
  "$EASYBLOBS_BASE/dev/easyblobs/test/hello/1.0.0/hello-1.0.0.jar" \
  --data-binary "@$jar")
case "$code" in 200|201) ;; *) echo "maven: PUT jar -> $code" >&2; exit 1 ;; esac

# READ BACK byte-for-byte: a mirror returning 200 with other bytes is broken.
curl -fsS -o /tmp/back.jar "$EASYBLOBS_BASE/dev/easyblobs/test/hello/1.0.0/hello-1.0.0.jar"
cmp -s /tmp/back.jar "$jar" || { echo "maven: bytes changed in the mirror" >&2; exit 1; }
echo "maven: built, ran and published hello-1.0.0.jar (bytes verified)"
