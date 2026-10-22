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
echo "nuget: built and packed $pkg"
