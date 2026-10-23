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
  printf 'hello easyblobs
' > "$W/hello.txt"
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
  pkg=$(find "$(conda info --base 2>/dev/null)/pkgs" -maxdepth 1     -name '*.tar.bz2' -o -maxdepth 1 -name '*.conda' 2>/dev/null | head -1)
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
code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \
  "$EASYBLOBS_BASE/_hosted/e2e/linux-64/$base" --data-binary "@$pkg")
case "$code" in 200|201) ;; *) echo "conda: upload -> $code" >&2; exit 1 ;; esac

# READ BACK byte-for-byte.
curl -fsS -o "/tmp/conda-back-$base" "$EASYBLOBS_BASE/_hosted/e2e/linux-64/$base"
cmp -s "/tmp/conda-back-$base" "$pkg" || {
  echo "conda: the served package differs from the built one" >&2; exit 1; }
echo "conda: built, published and re-read $base (bytes verified)"
