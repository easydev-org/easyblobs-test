#!/bin/sh
# conda: build a real package, then inspect what was produced.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD with conda-build, which is the real packager.
conda build . --output-folder /tmp/conda-out 2>&1 | tail -5

pkg=$(find /tmp/conda-out -name '*.tar.bz2' -o -name '*.conda' | head -1)
[ -n "$pkg" ] || { echo "conda: conda-build produced no package" >&2; exit 1; }
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
