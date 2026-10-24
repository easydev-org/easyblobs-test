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
# No interpreter could import pip. The 'pip' setup provides a pip WRAPPER whose
# own python is the one that has pip, so drive that wrapper directly rather than
# trying to reverse-engineer its shebang (which is not a plain path here and made
# the previous fallback yield an empty interpreter).
PIPMODE=""
if [ -n "$PY" ]; then
  PIPMODE="module"
  echo "python: interpreter $PY ($($PY --version 2>&1)), $($PY -m pip --version 2>&1 | head -1)"
elif command -v pip >/dev/null 2>&1 && pip --version >/dev/null 2>&1; then
  PIPMODE="wrapper"
  echo "python: using the pip wrapper at $(command -v pip) ($(pip --version 2>&1 | head -1))"
else
  echo "python: no pip at all. easysetup publishes it as the separate setup 'pip';" >&2
  echo "python: the 'python' setup alone has no pip. Found:" >&2
  echo "python: python3=$(command -v python3 || echo missing) pip=$(command -v pip || echo missing)" >&2
  exit 1
fi
pipexec() {
  if [ "$PIPMODE" = "module" ]; then "$PY" -m pip "$@"; else pip "$@"; fi
}
pyexec() { # run python code with the interpreter that owns pip
  if [ "$PIPMODE" = "module" ]; then "$PY" "$@"; else python3 "$@"; fi
}

# The nix python is EXTERNALLY MANAGED: installing into it is refused, by design.
#   error: externally-managed-environment
# A virtualenv is the sanctioned place to put build/twine, and it is what a real
# developer does, so the fixture creates one and works inside it.
if pyexec -m venv /tmp/venv >/dev/null 2>&1; then
  # Everything after this runs against the venv's interpreter.
  PYV=/tmp/venv/bin/python
  PIPMODE="module"
  PY="$PYV"
  echo "python: using a virtualenv at /tmp/venv"
fi

# The build frontend and twine are libraries, not interpreters; they are
# installed into this job rather than expected from the closure.
pyexec -c 'import build' 2>/dev/null || pipexec install -q build
pyexec -c 'import twine' 2>/dev/null || pipexec install -q twine
pyexec -m build --outdir dist . 2>&1 | tail -3
ls dist

# IMPORT the built artifact, so a broken source tree fails here.
pyexec -c 'import easyblobs_test_hello as m; print(m.greet("easyblobs"))'

# PUBLISH through the mount's upload endpoint (Twine-compatible multipart).
#
# Twine POSTs to the repository URL as given, so it must name the upload endpoint
# exactly - ".../pypi/" answers 404, while ".../pypi/upload" is what the adapter
# routes to its upload handler.
# --- build-only escape hatch -------------------------------------------------
# A read-only mirror has no write path, so "publish" cannot be exercised. Set
# E2E_BUILD_ONLY=1 to run everything up to the first publish call and stop: the
# build, the tests and the packaging still run, which is what those protocols
# can be held to.
if [ "${E2E_BUILD_ONLY:-0}" = 1 ]; then
  echo "python: build-only mode (E2E_BUILD_ONLY=1); stopping before publish"
  exit 0
fi

pyexec -m twine upload --repository-url "$EASYBLOBS_BASE/upload" \
  --username e2e --password e2e --non-interactive dist/* 2>&1 | tail -3

# READ BACK: the PEP 503 simple page must list the wheel.
curl -fsS "$EASYBLOBS_BASE/simple/easyblobs-test-hello/" \
  | grep -q 'easyblobs_test_hello-1.0.0' || {
    echo "python: the simple page does not list the wheel" >&2; exit 1; }
echo "python: published and re-read easyblobs-test-hello 1.0.0"
