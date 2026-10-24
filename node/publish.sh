#!/bin/sh
# node: build the package, publish it, read it back.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD: run the module, so a broken package fails here and not at publish time.
npm run --silent build

# PUBLISH. easyblobs accepts only scoped names (@scope/name); see the npm
# adapter's authorizePublish. The registry is the mount itself.
#
# The token has to be filed under the registry's OWN host, so it is derived from
# $EASYBLOBS_BASE rather than guessed: npm keys credentials by host and port, and
# a token filed under "localhost" is simply not offered to "127.0.0.1":
#   npm error code ENEEDAUTH
#   npm error need auth This command requires you to be logged in
#
# The credential key must be the URL npm DERIVES from the registry, which is not
# simply the host. npm nerfs a URI with `new URL('.', registry)`, treating the
# last segment as a FILENAME and keeping the directory:
#
#   registry  http://h:8080/artifacts/npm   ->  nerfed  //h:8080/artifacts/
#   registry  http://h:8080/artifacts/npm/  ->  nerfed  //h:8080/artifacts/npm/
#
# So the "//host/:_authToken" form every tutorial shows does NOT match a registry
# under a path, and npm reports
#   npm error code ENEEDAUTH
#   need auth This command requires you to be logged in to <registry>
# WITHOUT SENDING ANY REQUEST - which is why the server log stayed empty and the
# token looked ignored. Trailing slash on the registry, matching key. Verified
# against a real server: PUT -> 201, GET -> 200.
registry="${EASYBLOBS_BASE%/}/"
nerfed=$(printf '%s' "$registry" | sed -e 's|^https\?://||')
echo "node: registry=$registry"
{
  echo "registry=$registry"
  echo "//$nerfed:_authToken=e2e"
} > .npmrc
echo "node: .npmrc (token redacted)"; sed 's/_authToken=.*/_authToken=***/' .npmrc
export NPM_CONFIG_USERCONFIG="$PWD/.npmrc"
# --- build-only escape hatch -------------------------------------------------
# A read-only mirror has no write path, so "publish" cannot be exercised. Set
# E2E_BUILD_ONLY=1 to run everything up to the first publish call and stop: the
# build, the tests and the packaging still run, which is what those protocols
# can be held to.
if [ "${E2E_BUILD_ONLY:-0}" = 1 ]; then
  echo "node: build-only mode (E2E_BUILD_ONLY=1); stopping before publish"
  exit 0
fi

npm publish --registry "$registry" --userconfig "$PWD/.npmrc"

# READ BACK: the packument must list this version.
curl -fsS "$EASYBLOBS_BASE/@easyblobs-test%2Fhello" | grep -q '"1.0.0"' || {
  echo "node: published version is missing from the packument" >&2; exit 1; }
echo "node: published and re-read @easyblobs-test/hello@1.0.0"
