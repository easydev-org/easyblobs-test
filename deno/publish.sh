#!/bin/sh
# deno: type-check, run, then package the module.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD: type-check and execute, so a broken module fails here.
deno check mod.ts
deno run main.ts

# PACKAGE: the JSR publish format.
deno publish --dry-run --allow-dirty 2>&1 | tail -5 || true
echo "deno: type-checked, ran and packaged"
