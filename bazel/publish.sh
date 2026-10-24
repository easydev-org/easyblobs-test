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

# PUBLISH the built artefact under _hosted/<repo>/.
#
# I wrote earlier that bazel "has no adapter of its own ... a PUT is 405 by
# design". That was wrong: bazel is served by the generic `httpcache` adapter,
# which is a read-only pull-through cache everywhere EXCEPT the reserved
# "_hosted/<repo>/" prefix - and under that prefix it accepts PUT/GET/DELETE and
# generates an index. A bare PUT to /modules/... is a write to a read-only cache,
# which is where the 405 came from.
#
# The layout after the prefix is the BCR's own, so a bazel client can read it
# back the way it reads bcr.bazel.build.
# --- build-only escape hatch -------------------------------------------------
# A read-only mirror has no write path, so "publish" cannot be exercised. Set
# E2E_BUILD_ONLY=1 to run everything up to the first publish call and stop: the
# build, the tests and the packaging still run, which is what those protocols
# can be held to.
if [ "${E2E_BUILD_ONLY:-0}" = 1 ]; then
  echo "bazel: build-only mode (E2E_BUILD_ONLY=1); stopping before publish"
  exit 0
fi

code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \
  "$EASYBLOBS_BASE/_hosted/e2e/modules/easyblobs_hello/1.0.0/hello.txt" \
  --data-binary "@$out")
case "$code" in 200|201) ;; *) echo "bazel: upload -> $code" >&2; exit 1 ;; esac
curl -fsS -o /tmp/bazel-back \
  "$EASYBLOBS_BASE/_hosted/e2e/modules/easyblobs_hello/1.0.0/hello.txt"
cmp -s /tmp/bazel-back "$out" || {
  echo "bazel: the served file differs from the built one" >&2; exit 1; }
echo "bazel: resolved through the mirror, built //:hello, published and re-read it"
