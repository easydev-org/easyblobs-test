#!/bin/sh
# python: build a wheel and sdist, import the result, publish both.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD: produces dist/*, which also validates the package metadata.
# This drives the REAL packaging tools, because that is what a pypi client is:
# `python -m build` produces the wheel and sdist, and `twine` uploads them.
#
# easysetup publishes pip as its own setup ('pip', which is
# pythonPackages.pip and brings the interpreter with it) - the 'python' setup
# alone is a bare interpreter with no pip, so both names have to be requested.
pip_ok=0
if python3 -m pip --version >/dev/null 2>&1; then
  pip_ok=1
elif command -v pip >/dev/null 2>&1 || command -v pip3 >/dev/null 2>&1; then
  pip_ok=1
fi
if [ "$pip_ok" = 0 ]; then
  echo "python: no pip on PATH. easysetup publishes it as the separate setup" >&2
  echo "python: 'pip'; the 'python' setup alone has no pip. interpreter:" >&2
  echo "python: $(command -v python3 || echo missing)" >&2
  exit 1
fi
echo "python: $(python3 --version 2>&1), pip $(python3 -m pip --version 2>&1 | head -1)"

# The build frontend and twine are libraries, not interpreters; they are
# installed into this job rather than expected from the closure.
python3 -c 'import build' 2>/dev/null || python3 -m pip install -q build
python3 -c 'import twine' 2>/dev/null || python3 -m pip install -q twine
python3 -m build --outdir dist . 2>&1 | tail -3
ls dist

# IMPORT the built artifact, so a broken source tree fails here.
python3 -c 'import easyblobs_test_hello as m; print(m.greet("easyblobs"))'

# PUBLISH through the mount's upload endpoint (Twine-compatible multipart).
#
# Twine POSTs to the repository URL as given, so it must name the upload endpoint
# exactly - ".../pypi/" answers 404, while ".../pypi/upload" is what the adapter
# routes to its upload handler.
python3 -m twine upload --repository-url "$EASYBLOBS_BASE/upload" \
  --username e2e --password e2e --non-interactive dist/* 2>&1 | tail -3

# READ BACK: the PEP 503 simple page must list the wheel.
curl -fsS "$EASYBLOBS_BASE/simple/easyblobs-test-hello/" \
  | grep -q 'easyblobs_test_hello-1.0.0' || {
    echo "python: the simple page does not list the wheel" >&2; exit 1; }
echo "python: published and re-read easyblobs-test-hello 1.0.0"
