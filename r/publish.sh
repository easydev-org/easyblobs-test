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
echo "cran: built and installed $pkg"
