#!/bin/sh
# cpan: the real CPAN build cycle, then package the distribution.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD + TEST: Makefile.PL, make, make test.
perl Makefile.PL >/dev/null
make >/dev/null
make test 2>&1 | tail -5

# PACKAGE: the .tar.gz a CPAN index points at.
#
# `make dist` needs a MANIFEST, and a checkout has none - it is generated from
# the tree:
#   Problem opening MANIFEST: No such file or directory at ExtUtils/Manifest.pm
# `make manifest` writes it, which is what a CPAN author does before a release.
make manifest >/dev/null 2>&1 || true
make dist >/dev/null
dist=$(ls ./*.tar.gz | head -1)
[ -n "$dist" ] || { echo "cpan: make dist produced no tarball" >&2; exit 1; }

# PUBLISH it to the mount, then read it back.
base=$(basename "$dist")
# --- build-only escape hatch -------------------------------------------------
# A read-only mirror has no write path, so "publish" cannot be exercised. Set
# E2E_BUILD_ONLY=1 to run everything up to the first publish call and stop: the
# build, the tests and the packaging still run, which is what those protocols
# can be held to.
if [ "${E2E_BUILD_ONLY:-0}" = 1 ]; then
  echo "perl: build-only mode (E2E_BUILD_ONLY=1); stopping before publish"
  exit 0
fi

code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \
  "$EASYBLOBS_BASE/authors/id/E/EA/EASY${base}" --data-binary "@$dist")
case "$code" in 200|201) ;; *) echo "cpan: upload -> $code" >&2; exit 1 ;; esac
curl -fsS -o "/tmp/cpan-back" "$EASYBLOBS_BASE/authors/id/E/EA/EASY${base}"
cmp -s /tmp/cpan-back "$dist" || {
  echo "cpan: the served tarball differs from the built one" >&2; exit 1; }
echo "cpan: built, tested, published and re-read $base (bytes verified)"
