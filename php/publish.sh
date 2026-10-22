#!/bin/sh
# composer: resolve the autoloader, run the code, publish the manifest.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD: composer resolves and generates the autoloader, then the code runs.
composer install --no-interaction --quiet 2>/dev/null || composer dump-autoload --quiet
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
