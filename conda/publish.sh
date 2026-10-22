#!/bin/sh
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
code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \
  "$EASYBLOBS_BASE/linux-64/$base" --data-binary "@$pkg")
case "$code" in 200|201) ;; *) echo "conda: upload -> $code" >&2; exit 1 ;; esac

# READ BACK byte-for-byte.
curl -fsS -o "/tmp/conda-back-$base" "$EASYBLOBS_BASE/linux-64/$base"
cmp -s "/tmp/conda-back-$base" "$pkg" || {
  echo "conda: the served package differs from the built one" >&2; exit 1; }
echo "conda: built, published and re-read $base (bytes verified)"
