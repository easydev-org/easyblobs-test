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
hostport=$(printf '%s' "$EASYBLOBS_BASE" | sed -e 's|^https\?://||' -e 's|/.*||')
{
  echo "registry=$EASYBLOBS_BASE"
  echo "//$hostport/:_authToken=e2e"
  echo "always-auth=true"
} > .npmrc
# Three separate mechanisms, because a missed one is silent: npm decides "am I
# authenticated for this registry" BEFORE it sends anything, so an unread token
# gives ENEEDAUTH with no request on the wire.
#   1. the project .npmrc (always read),
#   2. NPM_CONFIG_USERCONFIG pointing at it explicitly ($HOME is /github/home in
#      a container, so ~/.npmrc is easy to miss),
#   3. the same key in environment form.
echo "node: .npmrc (token redacted)"; sed 's/_authToken=.*/_authToken=***/' .npmrc
export NPM_CONFIG_USERCONFIG="$PWD/.npmrc"
export "NPM_CONFIG_//$hostport/:_authToken=e2e"
npm publish --registry "$EASYBLOBS_BASE" --userconfig "$PWD/.npmrc"

# READ BACK: the packument must list this version.
curl -fsS "$EASYBLOBS_BASE/@easyblobs-test%2Fhello" | grep -q '"1.0.0"' || {
  echo "node: published version is missing from the packument" >&2; exit 1; }
echo "node: published and re-read @easyblobs-test/hello@1.0.0"
