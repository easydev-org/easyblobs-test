#!/bin/sh
# buf: lint and build a real proto module.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD: buf lint and buf build both parse the module.
buf lint
buf build -o /tmp/image.bin
[ -s /tmp/image.bin ] || { echo "buf: build produced no image" >&2; exit 1; }

# PUBLISH through the BSR push API, the same call `buf push` makes.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
python3 - "$TMP/push.json" <<'PY'
import base64, hashlib, json, os, sys

def shake(b):
    return hashlib.shake_256(b).digest(64)

paths = []
for root, _, names in os.walk("proto"):
    for n in names:
        paths.append(os.path.relpath(os.path.join(root, n)).replace(os.sep, "/"))
paths.sort()

blobs, manifest = [], []
for p in paths:
    c = open(p, "rb").read()
    d = shake(c)
    manifest.append("shake256:" + d.hex() + "  " + p + "
")
    blobs.append({"digest": {"digestType": 1, "digest": base64.b64encode(d).decode()},
                  "content": base64.b64encode(c).decode()})
mb = "".join(manifest).encode()
json.dump({"owner": "easyblobs-test", "repository": "hello",
           "manifest": {"digest": {"digestType": 1,
                                   "digest": base64.b64encode(shake(mb)).decode()},
                        "content": base64.b64encode(mb).decode()},
           "blobs": blobs, "tags": ["v1.0.0"]}, open(sys.argv[1], "w"))
PY
code=$(curl -sS -o "$TMP/resp.json" -w '%{http_code}' -X POST \
  "$EASYBLOBS_BASE/buf.alpha.registry.v1alpha1.PushService/PushManifestAndBlobs" \
  -H 'Content-Type: application/json' --data-binary "@$TMP/push.json")
case "$code" in 200|201) ;; *) echo "buf: push -> $code" >&2; exit 1 ;; esac
grep -q 'localModulePin' "$TMP/resp.json" || {
  echo "buf: push returned no module pin" >&2; exit 1; }
echo "buf: linted, built and published the module"
