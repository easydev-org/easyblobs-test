#!/bin/sh
# python: build a wheel and sdist, import the result, publish both.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD: produces dist/*, which also validates the package metadata.
# The build frontend and twine are not always present, and pip itself may be
# missing: easysetup's python setup is pkgs.python315, a bare interpreter with no
# pip, so `python3 -m pip install build` fails with
#   No module named pip
# A wheel is just a zip and an sdist is just a tar, and twine is only needed to
# POST them - so both are produced directly when pip is unavailable.
have_pip=0
python3 -m pip --version >/dev/null 2>&1 && have_pip=1
if [ "$have_pip" = 1 ]; then
  python3 -c 'import build' 2>/dev/null || python3 -m pip install -q build
  python3 -c 'import twine' 2>/dev/null || python3 -m pip install -q twine
fi
if [ "$have_pip" = 1 ] && python3 -c 'import build' 2>/dev/null; then
python3 -m build --outdir dist . 2>&1 | tail -3
else
  echo "python: pip/build unavailable; assembling the sdist and wheel directly"
  mkdir -p dist/pkgsrc/easyblobs_test_hello
  cp easyblobs_test_hello/__init__.py dist/pkgsrc/easyblobs_test_hello/
  cat > dist/pkgsrc/PKG-INFO <<'INFO'
Metadata-Version: 2.1
Name: easyblobs-test-hello
Version: 1.0.0
INFO
  ( cd dist/pkgsrc && tar -czf ../easyblobs_test_hello-1.0.0.tar.gz PKG-INFO easyblobs_test_hello )
  # A wheel is a zip whose name encodes the tags; the payload is the package.
  WHL=dist/easyblobs_test_hello-1.0.0-py3-none-any.whl
  ( cd dist/pkgsrc && zip -qr "../../$WHL" easyblobs_test_hello PKG-INFO )
  rm -rf dist/pkgsrc
fi
ls dist

# IMPORT the built artifact, so a broken source tree fails here.
python3 -c 'import easyblobs_test_hello as m; print(m.greet("easyblobs"))'

# PUBLISH through the mount's upload endpoint (Twine-compatible multipart).
#
# Twine POSTs to the repository URL as given, so it must name the upload endpoint
# exactly - ".../pypi/" answers 404, while ".../pypi/upload" is what the adapter
# routes to its upload handler.
if python3 -c 'import twine' 2>/dev/null; then
  python3 -m twine upload --repository-url "$EASYBLOBS_BASE/upload" \
    --username e2e --password e2e --non-interactive dist/* 2>&1 | tail -3
else
  # No twine: POST the same multipart body by hand. PyPI's upload form is a
  # regular multipart/form-data with :action=file_upload and a content field
  # per artefact, which curl can send without any python packaging toolkit.
  echo "python: twine unavailable; POSTing the multipart form directly"
  for f in dist/*.whl dist/*.tar.gz; do
    [ -f "$f" ] || continue
    code=$(curl -sS -o /tmp/pypi-resp.txt -w '%{http_code}' \
      -u e2e:e2e \
      -F ":action=file_upload" \
      -F "protocol_version=1" \
      -F "name=easyblobs-test-hello" \
      -F "version=1.0.0" \
      -F "content=@$f" \
      "$EASYBLOBS_BASE/upload")
    case "$code" in 200|201) ;; *) echo "python: upload $(basename "$f") -> $code" >&2; cat /tmp/pypi-resp.txt >&2; exit 1 ;; esac
  done
fi

# READ BACK: the PEP 503 simple page must list the wheel.
curl -fsS "$EASYBLOBS_BASE/simple/easyblobs-test-hello/" \
  | grep -q 'easyblobs_test_hello-1.0.0' || {
    echo "python: the simple page does not list the wheel" >&2; exit 1; }
echo "python: published and re-read easyblobs-test-hello 1.0.0"
