#!/bin/sh
# node: build the package, publish it, read it back.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD: run the module, so a broken package fails here and not at publish time.
npm run --silent build

# PUBLISH. easyblobs accepts only scoped names (@scope/name); see the npm
# adapter's authorizePublish. The registry is the mount itself.
npm publish --registry "$EASYBLOBS_BASE" --//localhost/:_authToken=e2e 2>/dev/null || \
  npm publish --registry "$EASYBLOBS_BASE" --_authToken=e2e

# READ BACK: the packument must list this version.
curl -fsS "$EASYBLOBS_BASE/@easyblobs-test%2Fhello" | grep -q '"1.0.0"' || {
  echo "node: published version is missing from the packument" >&2; exit 1; }
echo "node: published and re-read @easyblobs-test/hello@1.0.0"
