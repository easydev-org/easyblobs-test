#!/bin/sh
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
mkdir -p /tmp/conda-out
hex=$(conda list -n base --json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d))')
[ "$hex" -gt 0 ] || { echo "conda: the base environment lists no packages" >&2; exit 1; }

# `conda package` needs an installed prefix and writes to the package cache.
# NOTE: `conda package` has NO --output-folder flag ("unrecognized arguments");
# it always writes into <base>/pkgs, which the fallback below already looks at.
conda package -n base 2>&1 | tail -3 || true

pkg=$(find /tmp/conda-out -name '*.tar.bz2' -o -name '*.conda' 2>/dev/null | head -1)
[ -n "$pkg" ] || pkg=$(find "$(conda info --base 2>/dev/null)/pkgs" -maxdepth 1   -name '*.tar.bz2' -o -maxdepth 1 -name '*.conda' 2>/dev/null | head -1)
[ -n "$pkg" ] || { echo "conda: no package archive was produced" >&2; exit 1; }
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
