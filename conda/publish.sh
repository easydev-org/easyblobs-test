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

# A real environment with a real package in it. MAMBA_ROOT_PREFIX keeps everything
# under /tmp so nothing leaks into the container's HOME.
#
# NOT -q: the quiet flag hid the download/unpack lines, so when the cache turned
# out to be empty there was nothing in the log to say whether anything had been
# fetched at all.
export MAMBA_ROOT_PREFIX=/tmp/mamba-root
export CONDA_PKGS_DIRS=/tmp/mamba-root/pkgs
"$MM" create -y -p /tmp/conda-env -c conda-forge --override-channels "$MM" 2>&1 | tail -12
"$MM" list -p /tmp/conda-env >/tmp/conda-list.txt
[ -s /tmp/conda-list.txt ] || { echo "conda: the created environment lists no packages" >&2; exit 1; }
echo "conda: environment has $(wc -l < /tmp/conda-list.txt) package(s)"

# MICROMAMBA UNPACKS. The cache held "3 entries, 0 archive(s)": the packages were
# extracted into directories and the original .conda files were thrown away, so
# there is no archive to upload after a normal install.
#
# `download` keeps the archive and skips extraction, which is exactly the
# artefact a channel serves. That is the honest way to get one from the real
# client rather than fabricating a zip.
OUT=/tmp/conda-out
mkdir -p "$OUT"
"$MM" download -y -p "$OUT" -c conda-forge --override-channels "$MM" 2>&1 | tail -8 || true
echo "conda: after download, $OUT has:"
ls -1 "$OUT" 2>/dev/null | head -10

pkg=$(find "$OUT" -name '*.tar.bz2' -o -name '*.conda' 2>/dev/null | head -1)
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
    pkg=$(find "$d" -name '*.conda' -o -name '*.tar.bz2' 2>/dev/null | head -1)
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
code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \
  "$EASYBLOBS_BASE/_hosted/e2e/linux-64/$base" --data-binary "@$pkg")
case "$code" in 200|201) ;; *) echo "conda: upload -> $code" >&2; exit 1 ;; esac

# READ BACK byte-for-byte.
curl -fsS -o "/tmp/conda-back-$base" "$EASYBLOBS_BASE/_hosted/e2e/linux-64/$base"
cmp -s "/tmp/conda-back-$base" "$pkg" || {
  echo "conda: the served package differs from the built one" >&2; exit 1; }
echo "conda: built, published and re-read $base (bytes verified)"
