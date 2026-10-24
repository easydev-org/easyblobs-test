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

# PUBLISH under _hosted/<repo>/.
#
# cran is served by the generic `httpcache` adapter, which is a read-only
# pull-through cache for every path EXCEPT the reserved "_hosted/<repo>/" one -
# that prefix is what makes a request an upload instead of a cache lookup:
#   PUT /artifacts/cran/_hosted/<repo>/<native path>
# The middleware rewrites the prefix away and sets Hosted on the repo scope, so
# the adapter sees its normal shape. A bare PUT to src/contrib/ is a write to a
# read-only cache and is answered 405.
# --- build-only escape hatch -------------------------------------------------
# A read-only mirror has no write path, so "publish" cannot be exercised. Set
# E2E_BUILD_ONLY=1 to run everything up to the first publish call and stop: the
# build, the tests and the packaging still run, which is what those protocols
# can be held to.
if [ "${E2E_BUILD_ONLY:-0}" = 1 ]; then
  echo "r: build-only mode (E2E_BUILD_ONLY=1); stopping before publish"
  exit 0
fi

code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \
  "$EASYBLOBS_BASE/_hosted/e2e/src/contrib/$pkg" --data-binary "@$pkg")
case "$code" in 200|201) ;; *) echo "cran: upload -> $code" >&2; exit 1 ;; esac
curl -fsS -o /tmp/cran-back.tgz "$EASYBLOBS_BASE/_hosted/e2e/src/contrib/$pkg"
cmp -s /tmp/cran-back.tgz "$pkg" || {
  echo "cran: the served tarball differs from the built one" >&2; exit 1; }
echo "cran: built, installed, published and re-read $pkg (bytes verified)"
