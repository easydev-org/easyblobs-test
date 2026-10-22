#!/bin/sh
# bazel: resolve a bzlmod dependency through the mount and build a target.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# POINT bazel at the mirrored registry, so resolution goes through easyblobs.
cat > .bazelrc.local <<RC
common --registry=$EASYBLOBS_BASE
RC

# BUILD: resolving rules_go exercises the registry; the genrule proves the build
# actually ran.
bazel --bazelrc=.bazelrc.local mod graph 2>&1 | tail -5
bazel --bazelrc=.bazelrc.local build //:hello 2>&1 | tail -5

out=$(bazel --bazelrc=.bazelrc.local info bazel-bin 2>/dev/null)/hello.txt
[ -f "$out" ] || { echo "bazel: the target did not produce hello.txt" >&2; exit 1; }
grep -q 'hello easyblobs' "$out" || { echo "bazel: wrong target output" >&2; exit 1; }

# NO PUBLISH STEP.
#
# bazel has no adapter of its own: it is a read-only mirror of the Bazel Central
# Registry, served through the generic target. A PUT to /modules/... is answered
# 405 by design, so "publishing a bazel module" is not something this mirror
# offers. What the fixture CAN prove - and does above - is that a real bazel
# resolves a real module through the mirrored registry and builds a target.
echo "bazel: resolved a module through the mirrored registry and built //:hello"
echo "bazel: NOTE this mirror is read-only for bazel, so there is nothing to publish"
