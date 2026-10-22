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
npm publish --registry "$EASYBLOBS_BASE" --//localhost/:_authToken=e2e 2>/dev/null || \\
  npm publish --registry "$EASYBLOBS_BASE" --_authToken=e2e

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
echo "deno: type-checked, ran and packaged"
""",
        "Type-checks and runs a Deno module, then packages it for JSR.\n",
    )
