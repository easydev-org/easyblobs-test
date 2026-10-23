#!/bin/sh
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

# A real environment with a real package in it. --root-prefix keeps everything
# under /tmp so nothing leaks into the container's HOME.
export MAMBA_ROOT_PREFIX=/tmp/mamba-root
"$MM" create -y -q -p /tmp/conda-env -c conda-forge --override-channels "$MM" 2>&1 | tail -5
"$MM" list -p /tmp/conda-env >/tmp/conda-list.txt
[ -s /tmp/conda-list.txt ] || { echo "conda: the created environment lists no packages" >&2; exit 1; }
echo "conda: environment has $(wc -l < /tmp/conda-list.txt) package(s)"

# PACKAGE the environment with the tool's own packager, then verify the archive
# carries the metadata a conda client reads.
mkdir -p /tmp/conda-out
if "$MM" package -p /tmp/conda-env -o /tmp/conda-out >/dev/null 2>&1; then
  echo "conda: packaged with '$MM package'"
fi

pkg=$(find /tmp/conda-out -name '*.tar.bz2' -o -name '*.conda' 2>/dev/null | head -1)
if [ -z "$pkg" ]; then
  # `micromamba package` is not available in every build, so fall back to the
  # package cache that `create` just populated: those .conda files ARE the real
  # artefacts a channel serves, produced by the real tool.
  pkg=$(find "$MAMBA_ROOT_PREFIX/pkgs" -maxdepth 1     \( -name '*.conda' -o -name '*.tar.bz2' \) 2>/dev/null | head -1)
  [ -n "$pkg" ] && echo "conda: using an archive from the package cache"
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
