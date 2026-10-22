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
ls ./*.tar.gz
echo "cpan: built, tested and packaged"
