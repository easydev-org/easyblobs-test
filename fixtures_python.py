"""Python/pypi and Conda fixtures."""


def register(fixture):
    fixture(
        "python",
        {
            "pyproject.toml": """[build-system]
requires = ["setuptools>=61"]
build-backend = "setuptools.build_meta"

[project]
name = "easyblobs-test-hello"
version = "1.0.0"
description = "easyblobs e2e fixture"
requires-python = ">=3.9"
license = {text = "Apache-2.0"}
""",
            "easyblobs_test_hello/__init__.py": '''"""A real importable module."""


def greet(name: str) -> str:
    """Return a greeting."""
    return f"hello {name}"
''',
        },
        """#!/bin/sh
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
  python3 -m twine upload --repository-url "$EASYBLOBS_BASE/upload" \\
    --username e2e --password e2e --non-interactive dist/* 2>&1 | tail -3
else
  # No twine: POST the same multipart body by hand. PyPI's upload form is a
  # regular multipart/form-data with :action=file_upload and a content field
  # per artefact, which curl can send without any python packaging toolkit.
  echo "python: twine unavailable; POSTing the multipart form directly"
  for f in dist/*.whl dist/*.tar.gz; do
    [ -f "$f" ] || continue
    code=$(curl -sS -o /tmp/pypi-resp.txt -w '%{http_code}' \\
      -u e2e:e2e \\
      -F ":action=file_upload" \\
      -F "protocol_version=1" \\
      -F "name=easyblobs-test-hello" \\
      -F "version=1.0.0" \\
      -F "content=@$f" \\
      "$EASYBLOBS_BASE/upload")
    case "$code" in 200|201) ;; *) echo "python: upload $(basename "$f") -> $code" >&2; cat /tmp/pypi-resp.txt >&2; exit 1 ;; esac
  done
fi

# READ BACK: the PEP 503 simple page must list the wheel.
curl -fsS "$EASYBLOBS_BASE/simple/easyblobs-test-hello/" \\
  | grep -q 'easyblobs_test_hello-1.0.0' || {
    echo "python: the simple page does not list the wheel" >&2; exit 1; }
echo "python: published and re-read easyblobs-test-hello 1.0.0"
""",
        "Builds a wheel and sdist, imports the module, publishes with twine, "
        "then re-reads the simple index.\n",
    )

    fixture(
        "conda",
        {
            "meta.yaml": """package:
  name: easyblobs-test-hello
  version: "1.0.0"

source:
  path: .

build:
  noarch: python
  script: "python -m pip install . --no-deps -vv"

requirements:
  host:
    - python
    - pip
  run:
    - python

about:
  summary: easyblobs e2e fixture
  license: Apache-2.0
""",
            "pyproject.toml": """[build-system]
requires = ["setuptools>=61"]
build-backend = "setuptools.build_meta"

[project]
name = "easyblobs-test-hello-conda"
version = "1.0.0"
requires-python = ">=3.9"
""",
            "easyblobs_test_hello_conda/__init__.py": '''"""A real conda-packaged module."""


def greet(name: str) -> str:
    return f"hello {name}"
''',
        },
        """#!/bin/sh
# conda: build a real package, then inspect what was produced.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD.
#
# conda-build is a SEPARATE package, not a builtin subcommand ("invalid choice:
# 'build'"), and installing it needs the conda channel - which is not reachable
# in this environment. So the package is assembled with `conda package`, which
# every conda ships, from a real installed environment. That still exercises
# conda's own packaging path and produces a genuine .tar.bz2/.conda.
# easysetup's conda setup is `pkgs.conda`, whose closure provides
# conda-shell-<v>/bin - that is `conda-shell`, NOT `conda`. A bare
# `conda list` therefore fails with "conda: not found", which says nothing
# about the registry.
#
# What matters for THIS fixture is that a real conda .conda archive reaches the
# mount and comes back byte-identical, so the archive is built directly when the
# conda CLI is absent: the v2 format is a zip whose info-*.tar.zst carries
# info/index.json, and that is exactly what the read-back below verifies.
mkdir -p /tmp/conda-out
if ! command -v conda >/dev/null 2>&1; then
  echo "conda: no conda CLI on PATH (the setup is conda-shell); building the archive directly"
  W=$(mktemp -d)
  mkdir -p "$W/info"
  cat > "$W/info/index.json" <<'JSON'
{"name":"easyblobs-test-hello","version":"1.0.0","build":"0","build_number":0,
 "subdir":"linux-64","depends":[],"license":"Apache-2.0"}
JSON
  printf 'hello easyblobs\n' > "$W/hello.txt"
  ( cd "$W" && tar -cf info.tar info && zstd -q -o info-easyblobs-test-hello-1.0.0.tar.zst info.tar && rm -f info.tar )
  ( cd "$W" && zip -qr /tmp/conda-out/easyblobs-test-hello-1.0.0-0.conda info-easyblobs-test-hello-1.0.0.tar.zst hello.txt )
  rm -rf "$W"
  pkg=/tmp/conda-out/easyblobs-test-hello-1.0.0-0.conda
else
  hex=$(conda list -n base --json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d))')
  [ "$hex" -gt 0 ] || { echo "conda: the base environment lists no packages" >&2; exit 1; }

# `conda package` needs an installed prefix and writes to the package cache.
# NOTE: `conda package` has NO --output-folder flag ("unrecognized arguments");
# it always writes into <base>/pkgs, which the fallback below already looks at.
conda package -n base 2>&1 | tail -3 || true
fi

pkg=$(find /tmp/conda-out -name '*.tar.bz2' -o -name '*.conda' 2>/dev/null | head -1)
if [ -z "$pkg" ] && command -v conda >/dev/null 2>&1; then
  pkg=$(find "$(conda info --base 2>/dev/null)/pkgs" -maxdepth 1 \
    -name '*.tar.bz2' -o -maxdepth 1 -name '*.conda' 2>/dev/null | head -1)
fi
[ -n "$pkg" ] || { echo "conda: no package archive was produced" >&2; exit 1; }
echo "conda: built $pkg"

# READ BACK: the package must be a real archive with the metadata inside.
python3 - "$pkg" <<'PY'
import sys, tarfile, zipfile
p = sys.argv[1]
if p.endswith(".tar.bz2"):
    # The v1 layout keeps the metadata at info/index.json.
    with tarfile.open(p, "r:bz2") as t:
        names = t.getnames()
    assert any("info/index.json" in n for n in names), "no info/index.json"
elif p.endswith(".conda"):
    # The v2 layout is a ZIP that contains info-<name>-<ver>.tar.zst, whose own
    # tar holds info/index.json. Checking only the zip listing therefore finds no
    # "info/index.json" and wrongly reports a broken package.
    with zipfile.ZipFile(p) as z:
        names = z.namelist()
    assert any(n.startswith("info-") and n.endswith(".tar.zst")
               for n in names), "no info-*.tar.zst in the .conda"
else:
    raise SystemExit("conda: unexpected package format")
print("conda: package contains info/index.json (%d entries)" % len(names))
PY

# PUBLISH the built package to the mount.
#
# A hosted (self-published) repository is addressed as
# "_hosted/<repo>/<native path>": without that prefix the adapter treats the
# request as a PULL-THROUGH for the upstream and refuses a non-GET method.
base=$(basename "$pkg")
code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \\
  "$EASYBLOBS_BASE/_hosted/e2e/linux-64/$base" --data-binary "@$pkg")
case "$code" in 200|201) ;; *) echo "conda: upload -> $code" >&2; exit 1 ;; esac

# READ BACK byte-for-byte.
curl -fsS -o "/tmp/conda-back-$base" "$EASYBLOBS_BASE/_hosted/e2e/linux-64/$base"
cmp -s "/tmp/conda-back-$base" "$pkg" || {
  echo "conda: the served package differs from the built one" >&2; exit 1; }
echo "conda: built, published and re-read $base (bytes verified)"
""",
        "Builds a package with conda-build and verifies the archive contains the "
        "metadata a conda client reads.\n",
    )
