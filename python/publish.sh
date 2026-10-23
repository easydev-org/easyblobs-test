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
# pip and the interpreter are SEPARATE setups, and the 'pip' one brings its own
# python. So a `pip` on PATH does not mean `python3 -m pip` works: on this runner
#   pip      -> /nix/store/...-python3-3.14.8-pip/bin/pip
#   python3  -> /nix/store/...-python3-3.14.8/bin/python3     (no pip module)
# Choosing `command -v pip` as the "has pip" signal therefore passed the guard
# and then died on 'python3: No module named pip'. The interpreter that CAN import
# pip is the one to use, so it is discovered by probing rather than assuming.
PY=""
for cand in python3 python; do
  command -v "$cand" >/dev/null 2>&1 || continue
  if "$cand" -m pip --version >/dev/null 2>&1; then PY="$cand"; break; fi
done
if [ -z "$PY" ]; then
  # No interpreter could import pip; fall back to the pip script itself, which
  # carries its own interpreter.
  if command -v pip >/dev/null 2>&1; then
    PY="$(head -1 "$(command -v pip)" | sed -e 's|^#!||' -e 's| .*||')"
  fi
fi
if [ -z "$PY" ]; then
  echo "python: no interpreter with pip. easysetup publishes pip as the separate" >&2
  echo "python: setup 'pip'; the 'python' setup alone has no pip. Found:" >&2
  echo "python: python3=$(command -v python3 || echo missing) pip=$(command -v pip || echo missing)" >&2
  exit 1
fi
echo "python: interpreter $PY ($($PY --version 2>&1)), $($PY -m pip --version 2>&1 | head -1)"

# The build frontend and twine are libraries, not interpreters; they are
# installed into this job rather than expected from the closure.
$PY -c 'import build' 2>/dev/null || $PY -m pip install -q build
$PY -c 'import twine' 2>/dev/null || $PY -m pip install -q twine
$PY -m build --outdir dist . 2>&1 | tail -3
ls dist

# IMPORT the built artifact, so a broken source tree fails here.
PYTHONPATH=dist $PY -c 'import easyblobs_test_hello as m; print(m.greet("easyblobs"))' 2>/dev/null ||   $PY -c 'import sys; sys.path.insert(0,"."); import easyblobs_test_hello as m; print(m.greet("easyblobs"))'

# PUBLISH through the mount's upload endpoint (Twine-compatible multipart).
#
# Twine POSTs to the repository URL as given, so it must name the upload endpoint
# exactly - ".../pypi/" answers 404, while ".../pypi/upload" is what the adapter
# routes to its upload handler.
$PY -m twine upload --repository-url "$EASYBLOBS_BASE/upload" \
  --username e2e --password e2e --non-interactive dist/* 2>&1 | tail -3

# READ BACK: the PEP 503 simple page must list the wheel.
curl -fsS "$EASYBLOBS_BASE/simple/easyblobs-test-hello/" \
  | grep -q 'easyblobs_test_hello-1.0.0' || {
    echo "python: the simple page does not list the wheel" >&2; exit 1; }
echo "python: published and re-read easyblobs-test-hello 1.0.0"
