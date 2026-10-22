#!/bin/sh
# cran: build and check a real R package, then install it from the tarball.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD: R CMD build produces the .tar.gz a CRAN repository serves.
R CMD build . 2>&1 | tail -5
pkg=$(ls easyblobstesthello_*.tar.gz | head -1)
[ -n "$pkg" ] || { echo "cran: R CMD build produced no tarball" >&2; exit 1; }

# INSTALL from the tarball and call the code, so a broken package fails here.
mkdir -p /tmp/rlib
R CMD INSTALL --library=/tmp/rlib "$pkg" 2>&1 | tail -3
Rscript -e 'library(easyblobstesthello, lib.loc="/tmp/rlib"); cat(greet("easyblobs"), "\n")'

# PUBLISH the source package to the CRAN-style mount, then read it back.
code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \
  "$EASYBLOBS_BASE/src/contrib/$pkg" --data-binary "@$pkg")
case "$code" in 200|201) ;; *) echo "cran: upload -> $code" >&2; exit 1 ;; esac
curl -fsS -o /tmp/cran-back.tgz "$EASYBLOBS_BASE/src/contrib/$pkg"
cmp -s /tmp/cran-back.tgz "$pkg" || {
  echo "cran: the served tarball differs from the built one" >&2; exit 1; }
echo "cran: built, installed, published and re-read $pkg (bytes verified)"
