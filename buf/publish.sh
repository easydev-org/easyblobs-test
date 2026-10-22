#!/bin/sh
# buf: lint and build a real proto module.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD: buf lint and buf build both parse the module.
buf lint
buf build -o /tmp/image.bin
[ -s /tmp/image.bin ] || { echo "buf: build produced no image" >&2; exit 1; }
echo "buf: linted and built the module ($(wc -c < /tmp/image.bin) bytes)"
