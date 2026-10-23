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
pyexec -m twine upload --repository-url "$EASYBLOBS_BASE/upload" \\
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

# BUILD WITH THE REAL CLI.
#
# easysetup publishes micromamba for conda: it is a conda-compatible package
# manager in one static binary, with no base installation and no channel
# bootstrap. So this fixture drives the actual conda workflow instead of
# hand-assembling an archive - create an environment, install something into it
# and read the result back, which is what a conda client does.
#
# conda-build (the recipe packager) is deliberately not used: it needs the
# conda-forge channel and compiles a recipe, which is a different subject from
# whether the registry serves a channel correctly.
MM=micromamba
command -v "$MM" >/dev/null 2>&1 || MM=conda
command -v "$MM" >/dev/null 2>&1 || {
  echo "conda: neither micromamba nor conda is on PATH; easysetup publishes" >&2
  echo "conda: 'micromamba' for this protocol - check the setup list" >&2
  exit 1; }
echo "conda: using $MM ($("$MM" --version 2>&1 | head -1))"

# A real environment with a real package in it. MAMBA_ROOT_PREFIX keeps everything
# under /tmp so nothing leaks into the container's HOME.
#
# NOT -q: the quiet flag hid the download/unpack lines, so when the cache turned
# out to be empty there was nothing in the log to say whether anything had been
# fetched at all.
export MAMBA_ROOT_PREFIX=/tmp/mamba-root
# Tell micromamba where to cache packages instead of inferring it later: the
# fixture needs a stable path to find the downloaded .conda artefacts in.
export CONDA_PKGS_DIRS=/tmp/mamba-root/pkgs
"$MM" create -y -p /tmp/conda-env -c conda-forge --override-channels "$MM" 2>&1 | tail -12
"$MM" list -p /tmp/conda-env >/tmp/conda-list.txt
[ -s /tmp/conda-list.txt ] || { echo "conda: the created environment lists no packages" >&2; exit 1; }
echo "conda: environment has $(wc -l < /tmp/conda-list.txt) package(s)"

# Where did the archives actually land? Printing the candidates beats guessing a
# path and then reporting "no package archive was produced" for an environment
# that demonstrably has packages installed.
echo "conda: package-cache candidates:"
for d in "${CONDA_PKGS_DIRS:-}" "$MAMBA_ROOT_PREFIX/pkgs" /tmp/mamba-root/pkgs \
         "$HOME/.mamba/pkgs" "$HOME/.conda/pkgs"; do
  [ -n "$d" ] || continue
  if [ -d "$d" ]; then
    echo "  $d: $(ls -1 "$d" 2>/dev/null | wc -l) entries, $(ls -1 "$d" 2>/dev/null | grep -cE '\.(conda|tar\.bz2)$' || true) archive(s)"
  else
    echo "  $d: (absent)"
  fi
done

# PACKAGE the environment with the tool's own packager, then verify the archive
# carries the metadata a conda client reads.
mkdir -p /tmp/conda-out
if "$MM" package -p /tmp/conda-env -o /tmp/conda-out >/dev/null 2>&1; then
  echo "conda: packaged with '$MM package'"
fi

pkg=$(find /tmp/conda-out -name '*.tar.bz2' -o -name '*.conda' 2>/dev/null | head -1)
if [ -z "$pkg" ]; then
  # `micromamba package` is not available in every build, so fall back to the
  # package cache that `create` populated: those .conda files ARE the real
  # artefacts a channel serves, produced by the real tool.
  #
  # The cache is NOT necessarily $MAMBA_ROOT_PREFIX/pkgs - micromamba honours
  # $CONDA_PKGS_DIRS and otherwise derives its own location, so guessing one path
  # searched nothing and reported "no package archive was produced" for an
  # environment that had just installed five packages. Whatever the tool reports
  # is what gets searched.
  for d in "${CONDA_PKGS_DIRS:-}" "$MAMBA_ROOT_PREFIX/pkgs" /tmp/mamba-root/pkgs "$HOME/.mamba/pkgs"; do
    [ -n "$d" ] || continue
    [ -d "$d" ] || continue
    pkg=$(find "$d" -maxdepth 1 \( -name '*.conda' -o -name '*.tar.bz2' \) 2>/dev/null | head -1)
    [ -n "$pkg" ] && { echo "conda: using $pkg from the package cache"; break; }
  done
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
