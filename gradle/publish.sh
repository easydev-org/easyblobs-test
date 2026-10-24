#!/bin/sh
# gradle: a real gradle build, using the mount as its maven repository.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD with gradle itself (not mvn): this is what the fixture is for.
gradle --no-daemon --quiet build
jar=$(ls build/libs/*.jar | head -1)
[ -s "$jar" ] || { echo "gradle: no jar produced" >&2; exit 1; }

# gradle, because the fixture is about gradle: running the JAR it produced is the
# assertion that the build really worked.
java -cp "$jar" dev.easyblobs.test.gradle.Main

# PUBLISH the jar to the mount: a build that never reaches the registry does not
# test the registry. The coordinate matches THIS project's group, so it cannot
# overwrite maven's dev.easyblobs.test:hello.
url="$EASYBLOBS_BASE/dev/easyblobs/test/gradle/hello/1.0.0/hello-1.0.0.jar"
code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT "$url" --data-binary "@$jar")
case "$code" in 200|201) ;; *) echo "gradle: PUT jar -> $code" >&2; exit 1 ;; esac

# READ BACK byte-for-byte.
curl -fsS -o /tmp/gradle-back.jar "$url"
cmp -s /tmp/gradle-back.jar "$jar" || {
  echo "gradle: bytes changed in the mirror" >&2; exit 1; }
echo "gradle: built, ran and published hello-1.0.0.jar (bytes verified)"
