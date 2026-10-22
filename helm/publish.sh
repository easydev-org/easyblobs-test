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
echo "helm: linted, rendered and packaged $chart"
