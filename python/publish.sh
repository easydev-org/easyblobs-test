#!/bin/sh
# python: build a wheel and sdist, import the result, publish both.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD: produces dist/*, which also validates the package metadata.
# The build frontend and twine are not always present on a bare runner; installing
# them is part of preparing the toolchain, not a workaround.
python3 -c 'import build' 2>/dev/null || python3 -m pip install -q build
python3 -c 'import twine' 2>/dev/null || python3 -m pip install -q twine
python3 -m build --outdir dist . 2>&1 | tail -3
ls dist

# IMPORT the built artifact, so a broken source tree fails here.
python3 -c 'import easyblobs_test_hello as m; print(m.greet("easyblobs"))'

# PUBLISH through the mount's upload endpoint (Twine-compatible multipart).
python3 -m twine upload --repository-url "$EASYBLOBS_BASE/" \
  --username e2e --password e2e --non-interactive dist/* 2>&1 | tail -3

# READ BACK: the PEP 503 simple page must list the wheel.
curl -fsS "$EASYBLOBS_BASE/simple/easyblobs-test-hello/" \
  | grep -q 'easyblobs_test_hello-1.0.0' || {
    echo "python: the simple page does not list the wheel" >&2; exit 1; }
echo "python: published and re-read easyblobs-test-hello 1.0.0"
