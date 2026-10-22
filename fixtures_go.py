"""Go module and Bazel fixtures."""


def register(fixture):
    fixture(
        "go",
        {
            "go.mod": """module example.com/easyblobs-test/hello

go 1.21
""",
            "hello.go": """// Package hello is a real module the go toolchain must build.
package hello

import "fmt"

// Greet returns a greeting.
func Greet(name string) string {
\treturn fmt.Sprintf("hello %s", name)
}
""",
            "hello_test.go": """package hello

import "testing"

func TestGreet(t *testing.T) {
\tif got := Greet("easyblobs"); got != "hello easyblobs" {
\t\tt.Fatalf("got %q", got)
\t}
}
""",
            "cmd/app/main.go": """package main

import (
\t"fmt"

\t"example.com/easyblobs-test/hello"
)

func main() { fmt.Println(hello.Greet("easyblobs")) }
""",
        },
        """#!/bin/sh
# go: build, test and publish this module as a module zip.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD + TEST, so a broken toolchain or module fails here.
go build ./...
go test ./...
go run ./cmd/app

# PUBLISH. The adapter serves .mod by extracting go.mod from the stored zip, so
# the module must be uploaded as the canonical zip - a plain text body would
# produce a module the go toolchain cannot consume.
MOD="example.com/easyblobs-test/hello"
VER="v1.0.0"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/zip/$MOD@$VER"
cp go.mod hello.go "$TMP/zip/$MOD@$VER/"
( cd "$TMP/zip" && zip -qr "$TMP/mod.zip" . )

code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \\
  "$EASYBLOBS_BASE/upload?name=$MOD&version=$VER" \\
  -H 'Content-Type: application/octet-stream' --data-binary "@$TMP/mod.zip")
case "$code" in 200|201) ;; *) echo "go: upload -> $code" >&2; exit 1 ;; esac

# READ BACK: the served go.mod must be the one shipped, not a phantom.
curl -fsS "$EASYBLOBS_BASE/$MOD/@v/$VER.mod" | grep -q "module $MOD" || {
  echo "go: served go.mod does not declare the module path" >&2; exit 1; }
curl -fsS -o /dev/null "$EASYBLOBS_BASE/$MOD/@v/$VER.info" || {
  echo "go: no .info" >&2; exit 1; }
echo "go: published and re-read $MOD@$VER"
""",
        "Builds and tests a real module, uploads the canonical module zip, then "
        "re-reads `.mod` and `.info` - the shapes the go toolchain requests.\n",
    )

    fixture(
        "bazel",
        {
            "MODULE.bazel": """module(name = "easyblobs_test_hello", version = "1.0.0")

bazel_dep(name = "rules_go", version = "0.50.1")
""",
            "BUILD.bazel": """genrule(
    name = "hello",
    outs = ["hello.txt"],
    cmd = "echo 'hello easyblobs' > $@",
)
""",
            # bzlmod must be ON: the fixture's whole purpose is resolving a
            # registry dependency. An earlier version set both --noenable_bzlmod
            # and --enable_bzlmod, which conflicts and aborts before any work.
            ".bazelrc": "common --enable_bzlmod\n",
        },
        """#!/bin/sh
# bazel: resolve a bzlmod dependency through the mount and build a target.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# POINT bazel at the mirrored registry, so resolution goes through easyblobs.
cat > .bazelrc.local <<RC
common --registry=$EASYBLOBS_BASE
RC

# BUILD: resolving rules_go exercises the registry; the genrule proves the build
# actually ran.
bazel --bazelrc=.bazelrc.local mod graph 2>&1 | tail -5
bazel --bazelrc=.bazelrc.local build //:hello 2>&1 | tail -5

out=$(bazel --bazelrc=.bazelrc.local info bazel-bin 2>/dev/null)/hello.txt
[ -f "$out" ] || { echo "bazel: the target did not produce hello.txt" >&2; exit 1; }
grep -q 'hello easyblobs' "$out" || { echo "bazel: wrong target output" >&2; exit 1; }

# PUBLISH the built artifact to the mount (the BCR layout: modules/<name>/...),
# then read it back. Resolution through the registry was already exercised above.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
name=rules_hello
code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \\
  "$EASYBLOBS_BASE/modules/$name/1.0.0/hello.txt" --data-binary "@$out")
case "$code" in 200|201) ;; *) echo "bazel: upload -> $code" >&2; exit 1 ;; esac
curl -fsS -o /tmp/bazel-back "$EASYBLOBS_BASE/modules/$name/1.0.0/hello.txt"
cmp -s /tmp/bazel-back "$out" || {
  echo "bazel: the served file differs" >&2; exit 1; }
echo "bazel: resolved through the mirror, built //:hello and published it"
""",
        "Resolves a real module dependency through the mirrored BCR with `bazel mod "
        "graph`, then builds a target and checks its output.\n",
    )
