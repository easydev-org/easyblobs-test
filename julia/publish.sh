#!/bin/sh
# julia: instantiate and run this Julia package.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD with the real package manager, then call into the package.
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. -e 'using EasyblobsTestHello; println(EasyblobsTestHello.greet("easyblobs"))'
echo "julia: instantiated and ran the package"
