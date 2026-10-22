#!/bin/sh
# cpan: the real CPAN build cycle, then package the distribution.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD + TEST: Makefile.PL, make, make test.
perl Makefile.PL >/dev/null
make >/dev/null
make test 2>&1 | tail -5

# PACKAGE: the .tar.gz a CPAN index points at.
make dist >/dev/null
dist=$(ls ./*.tar.gz | head -1)
[ -n "$dist" ] || { echo "cpan: make dist produced no tarball" >&2; exit 1; }

# PUBLISH it to the mount, then read it back.
base=$(basename "$dist")
code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \
  "$EASYBLOBS_BASE/authors/id/E/EA/EASY${base}" --data-binary "@$dist")
case "$code" in 200|201) ;; *) echo "cpan: upload -> $code" >&2; exit 1 ;; esac
curl -fsS -o "/tmp/cpan-back" "$EASYBLOBS_BASE/authors/id/E/EA/EASY${base}"
cmp -s /tmp/cpan-back "$dist" || {
  echo "cpan: the served tarball differs from the built one" >&2; exit 1; }
echo "cpan: built, tested, published and re-read $base (bytes verified)"
