#!/bin/sh
# helm: lint, template and package a real chart.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD: lint and template, so a broken chart fails here.
helm lint .
helm template e2e . | grep -q 'hello easyblobs' || {
  echo "helm: the rendered manifest lacks the value" >&2; exit 1; }

# PACKAGE: the .tgz a chart repository serves.
mkdir -p /tmp/charts
helm package . -d /tmp/charts >/dev/null
chart=$(ls /tmp/charts/easyblobs-test-hello-1.0.0.tgz)
[ -s "$chart" ] || { echo "helm: no chart produced" >&2; exit 1; }

# PUBLISH the chart to the mount. The chartmuseum-style push names the chart and
# version explicitly, because the server records what it is given.
code=$(curl -sS -o /dev/null -w '%{http_code}' -X POST \
  "$EASYBLOBS_BASE/api/charts?name=easyblobs-test-hello&version=1.0.0" \
  -H 'Content-Type: application/octet-stream' --data-binary "@$chart")
case "$code" in 200|201) ;; *) echo "helm: upload -> $code" >&2; exit 1 ;; esac

# READ BACK: the served chart must be byte-identical.
curl -fsS -o /tmp/helm-back.tgz \
  "$EASYBLOBS_BASE/charts/easyblobs-test-hello-1.0.0.tgz"
cmp -s /tmp/helm-back.tgz "$chart" || {
  echo "helm: the served chart differs from the one uploaded" >&2; exit 1; }
echo "helm: linted, rendered, published and re-read $chart (bytes verified)"
