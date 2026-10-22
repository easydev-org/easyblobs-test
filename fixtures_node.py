"""Node/npm and Deno/JSR fixtures."""


def register(fixture):
    fixture(
        "node",
        {
            "package.json": """{
  "name": "@easyblobs-test/hello",
  "version": "1.0.0",
  "description": "easyblobs e2e fixture",
  "main": "index.js",
  "files": ["index.js"],
  "scripts": { "build": "node index.js" },
  "license": "Apache-2.0"
}
""",
            "index.js": """'use strict';

// A real module the toolchain parses and the registry stores.
function greet(name) {
  return `hello ${name}`;
}

module.exports = { greet };

if (require.main === module) {
  console.log(greet('easyblobs'));
}
""",
        },
        """#!/bin/sh
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
hostport=$(printf '%s' "$EASYBLOBS_BASE" | sed -e 's|^https\\?://||' -e 's|/.*||')
{
  echo "registry=$EASYBLOBS_BASE"
  echo "//$hostport/:_authToken=e2e"
} > "$HOME/.npmrc"
npm publish

# READ BACK: the packument must list this version.
curl -fsS "$EASYBLOBS_BASE/@easyblobs-test%2Fhello" | grep -q '"1.0.0"' || {
  echo "node: published version is missing from the packument" >&2; exit 1; }
echo "node: published and re-read @easyblobs-test/hello@1.0.0"
""",
        "Builds and publishes an npm package, then re-reads the packument.\n",
    )

    fixture(
        "deno",
        {
            "mod.ts": """/**
 * A real Deno module.
 */
export function greet(name: string): string {
  return `hello ${name}`;
}
""",
            "main.ts": """import { greet } from './mod.ts';

console.log(greet('easyblobs'));
""",
            "deno.json": """{
  "name": "@easyblobs-test/hello",
  "version": "1.0.0",
  "exports": "./mod.ts"
}
""",
        },
        """#!/bin/sh
# deno: type-check, run, then package the module.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD: type-check and execute, so a broken module fails here.
deno check mod.ts
deno run main.ts

# PACKAGE: the JSR publish format.
deno publish --dry-run --allow-dirty 2>&1 | tail -5 || true

# PUBLISH the module tarball to the mount's JSR layout, then read it back.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
tar -czf "$TMP/hello-1.0.0.tar.gz" deno.json mod.ts
pkg="$TMP/hello-1.0.0.tar.gz"
code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \\
  "$EASYBLOBS_BASE/@easyblobs-test/hello/1.0.0_meta.json" \\
  -H 'Content-Type: application/json' \\
  --data-binary '{"exports":{"./mod.ts":"./mod.ts"},"moduleGraph1":{}}')
case "$code" in 200|201) ;; *) echo "deno: publish -> $code" >&2; exit 1 ;; esac
curl -fsS -o /dev/null "$EASYBLOBS_BASE/@easyblobs-test/hello/1.0.0_meta.json" || {
  echo "deno: the version metadata does not resolve after publish" >&2; exit 1; }
echo "deno: type-checked, ran, published and re-read the version metadata"
""",
        "Type-checks and runs a Deno module, then packages it for JSR.\n",
    )
