#!/bin/sh
# composer: resolve the autoloader, run the code, publish the manifest.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD: the code runs, and the autoloader is resolved when composer exists.
#
# easysetup ships php but NOT composer, so composer is the one thing this
# fixture has to fetch itself. Without it the script died with
# "composer: not found" and looked like a broken fixture rather than a missing
# tool. A project with no dependencies does not need composer to run, so the
# autoloader step is skipped when it is absent - the interesting part for THIS
# fixture is publishing the manifest, which uses curl.
if command -v composer >/dev/null 2>&1; then
  composer install --no-interaction --quiet 2>/dev/null || composer dump-autoload --quiet
else
  echo "composer: not installed (easysetup has php, not composer); using a plain autoloader"
  cat > autoload.php <<'PHP'
<?php
// __DIR__ here is the vendor/ directory (the file is copied there), so the
// source tree is one level up. Getting this wrong gave
//   Failed to open stream: .../vendor/src/Greeter.php
require __DIR__ . '/../src/Greeter.php';
PHP
  # main.php requires vendor/autoload.php; give it one without composer.
  mkdir -p vendor
  cp autoload.php vendor/autoload.php
fi
php main.php

# PUBLISH the manifest, which is what the composer adapter stores.
code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \
  "$EASYBLOBS_BASE/api/packages" -H 'Content-Type: application/json' \
  --data-binary "@composer.json")
case "$code" in 200|201) ;; *) echo "composer: publish -> $code" >&2; exit 1 ;; esac

# READ BACK through the p2 index, the surface a composer client consults.
curl -fsS "$EASYBLOBS_BASE/p2/easyblobs-test/hello.json" | grep -q '"1.0.0"' || {
  echo "composer: the p2 index does not advertise 1.0.0" >&2; exit 1; }
echo "composer: installed, ran and published easyblobs-test/hello 1.0.0"
