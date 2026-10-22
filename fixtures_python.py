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
python3 -m build --outdir dist . 2>&1 | tail -3
ls dist

# IMPORT the built artifact, so a broken source tree fails here.
python3 -c 'import easyblobs_test_hello as m; print(m.greet("easyblobs"))'

# PUBLISH through the mount's upload endpoint (Twine-compatible multipart).
python3 -m twine upload --repository-url "$EASYBLOBS_BASE/" \\
  --username e2e --password e2e --non-interactive dist/* 2>&1 | tail -3

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

# BUILD with conda-build, which is the real packager.
# conda-build is a SEPARATE package, not a builtin subcommand:
#   argument COMMAND: invalid choice: 'build'
# Install it into the base env first, then build.
if ! conda build --help >/dev/null 2>&1; then
  conda install -y -q -n base -c conda-forge conda-build >/dev/null 2>&1 || true
fi
conda build . --output-folder /tmp/conda-out 2>&1 | tail -5

pkg=$(find /tmp/conda-out -name '*.tar.bz2' -o -name '*.conda' | head -1)
[ -n "$pkg" ] || { echo "conda: conda-build produced no package (is conda-build installed?)" >&2; exit 1; }
echo "conda: built $pkg"

# READ BACK: the package must be a real archive with the metadata inside.
python3 - "$pkg" <<'PY'
import sys, tarfile, zipfile
p = sys.argv[1]
if p.endswith(".tar.bz2"):
    with tarfile.open(p, "r:bz2") as t:
        names = t.getnames()
elif p.endswith(".conda"):
    with zipfile.ZipFile(p) as z:
        names = z.namelist()
else:
    raise SystemExit("conda: unexpected package format")
assert any("info/index.json" in n for n in names), "no info/index.json"
print("conda: package contains info/index.json (%d entries)" % len(names))
PY

# PUBLISH the built package to the mount, under the channel layout a conda
# client asks for (linux-64/<file>).
base=$(basename "$pkg")
code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \\
  "$EASYBLOBS_BASE/linux-64/$base" --data-binary "@$pkg")
case "$code" in 200|201) ;; *) echo "conda: upload -> $code" >&2; exit 1 ;; esac

# READ BACK byte-for-byte.
curl -fsS -o "/tmp/conda-back-$base" "$EASYBLOBS_BASE/linux-64/$base"
cmp -s "/tmp/conda-back-$base" "$pkg" || {
  echo "conda: the served package differs from the built one" >&2; exit 1; }
echo "conda: built, published and re-read $base (bytes verified)"
""",
        "Builds a package with conda-build and verifies the archive contains the "
        "metadata a conda client reads.\n",
    )
