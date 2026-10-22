#!/bin/sh
# sbt: a real sbt build that resolves through the mirrored Ivy repository.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD with sbt itself; the resolvers point at the mount.
sbt -batch -Dsbt.log.noformat=true compile 2>&1 | tail -5

out=$(find target -name '*.class' | head -1)
[ -n "$out" ] || { echo "sbt: compilation produced no classes" >&2; exit 1; }
echo "sbt: compiled through the mirrored Ivy repository"
