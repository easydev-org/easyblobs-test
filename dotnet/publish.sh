#!/bin/sh
# nuget: restore, build and pack a real .NET project.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD + PACK: dotnet pack produces the .nupkg a nuget feed serves.
dotnet build --nologo -v quiet
dotnet pack --nologo -v quiet -o /tmp/nupkg
pkg=$(ls /tmp/nupkg/*.nupkg | head -1)
[ -n "$pkg" ] || { echo "nuget: dotnet pack produced no nupkg" >&2; exit 1; }

# The nupkg must be a real zip with a .nuspec inside - that is what a client
# reads the id and version from.
python3 - "$pkg" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    names = z.namelist()
assert any(n.endswith(".nuspec") for n in names), "no .nuspec in the nupkg"
print("nuget: nupkg contains the .nuspec (%d entries)" % len(names))
PY

# PUBLISH through the SINGLE upload endpoint. nuget is not a path-style push:
# the flat container (/v3/flatcontainer/...) is READ-only and a PUT there is 404;
# publishing is `PUT /v3/package` with the nupkg as the body.
code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \
  "$EASYBLOBS_BASE/v3/package" -H 'Content-Type: application/octet-stream' \
  --data-binary "@$pkg")
case "$code" in 200|201) ;; *) echo "nuget: upload -> $code" >&2; exit 1 ;; esac

# READ BACK from the flat container, which is where a nuget client looks.
curl -fsS -o /tmp/nuget-back \
  "$EASYBLOBS_BASE/v3/flatcontainer/easyblobs.test.hello/1.0.0/easyblobs.test.hello.1.0.0.nupkg"
cmp -s /tmp/nuget-back "$pkg" || {
  echo "nuget: the served nupkg differs from the built one" >&2; exit 1; }
echo "nuget: built, packed, published to /v3/package and re-read (bytes verified)"
