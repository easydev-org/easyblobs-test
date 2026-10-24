#!/usr/bin/env python3
"""gen.py - generate the easyblobs-test fixture repository.

Every language/toolchain gets a REAL project that can be BUILT and PUBLISHED, so
the CI suites can clone this repo and drive the real toolchain against
easyblobs instead of hand-writing throwaway files inside each test script.

Why a generator: the per-language differences are mechanical (a manifest
filename, a build command, a publish command). Keeping them in one table means a
new language is one entry and the whole repo stays consistent.

Layout:

    <language>/README.md    what this fixture proves
    <language>/publish.sh   build + publish + read back, run by CI
    <language>/...          the real project

Every publish.sh reads EASYBLOBS_BASE (the mount under test) and
  1. builds the project, so a broken toolchain fails before publishing,
  2. publishes it through the mount,
  3. reads it back and compares content where the ecosystem allows it.
"""

import os
import stat
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."

FIXTURES = {}


def write(path, content, mode=None):
    full = os.path.join(ROOT, path)
    d = os.path.dirname(full)
    if d:
        os.makedirs(d, exist_ok=True)
    with open(full, "w", encoding="utf-8") as f:
        f.write(content)
    if mode is not None:
        os.chmod(full, mode)


EXEC = stat.S_IRWXU | stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH


# Some protocols are read-only MIRRORS: the adapter serves an upstream registry
# and has no write path, so there is nothing to publish through it. Their
# fixtures are still real buildable projects, and building one is worth doing -
# it proves the toolchain works on real source and that the client can resolve
# against the mount. So every publish.sh gets the same escape hatch:
#
#     E2E_BUILD_ONLY=1 sh ./publish.sh
#
# runs everything up to the first publish call and stops. Injected here, once,
# rather than written into 21 scripts by hand.
BUILD_ONLY_GUARD = """\

# --- build-only escape hatch -------------------------------------------------
# A read-only mirror has no write path, so "publish" cannot be exercised. Set
# E2E_BUILD_ONLY=1 to run everything up to the first publish call and stop: the
# build, the tests and the packaging still run, which is what those protocols
# can be held to.
if [ "${E2E_BUILD_ONLY:-0}" = 1 ]; then
  echo "%s: build-only mode (E2E_BUILD_ONLY=1); stopping before publish"
  exit 0
fi
"""


def add_build_only_guard(name, script):
    """Insert the guard immediately before the first publish action.

    The fixtures all follow the same shape - build, then publish - so the first
    publish call is the boundary. Recognising the call sites explicitly (rather
    than guessing at a line number) keeps this honest: if a script stops
    publishing the way this expects, the guard simply lands at the end, which is
    still correct.
    """
    markers = (
        "\ncode=$(curl",       # the common path-style publish
        "\ncargo publish",
        "\nnpm publish",
        "\ngem push",
        "\ntwine upload",
        "\n$PY -m twine upload",
        "\npyexec -m twine upload",
        "\n\"$MM\" download",
    )
    best = -1
    for m in markers:
        i = script.find(m)
        if i >= 0 and (best < 0 or i < best):
            best = i
    if best < 0:
        # No publish step at all (bazel already says so explicitly) - put the
        # guard at the end, where it is a no-op that still prints the mode.
        return script.rstrip("\n") + BUILD_ONLY_GUARD % name + ""
    return script[:best] + BUILD_ONLY_GUARD % name + script[best:]


def fixture(name, files, publish, readme):
    FIXTURES[name] = {"files": files, "publish": publish, "readme": readme}


def main():
    import fixtures_node
    import fixtures_python
    import fixtures_go
    import fixtures_java
    import fixtures_rust
    import fixtures_others

    for mod in (fixtures_node, fixtures_python, fixtures_go, fixtures_java,
                fixtures_rust, fixtures_others):
        mod.register(fixture)

    for name, spec in FIXTURES.items():
        for path, content in spec["files"].items():
            write(os.path.join(name, path), content)
        write(os.path.join(name, "publish.sh"),
              add_build_only_guard(name, spec["publish"]), EXEC)
        write(os.path.join(name, "README.md"), spec["readme"])

    listing = "\n".join(f"- `{n}`" for n in sorted(FIXTURES))
    write(
        "README.md",
        "# easyblobs-test\n"
        "\n"
        "Real, buildable fixtures for every language/toolchain that easyblobs\n"
        "mirrors.\n"
        "\n"
        "A test suite CLONES this repo and runs the real toolchain against\n"
        "easyblobs - build, publish, read back - instead of writing throwaway\n"
        "files inside each test script. When a fixture builds and publishes here\n"
        "the toolchain works; when it does not, the failure is in the toolchain or\n"
        "the protocol, never in a hand-written stub.\n"
        "\n"
        "## Layout\n"
        "\n"
        "    <language>/README.md    what this fixture proves\n"
        "    <language>/publish.sh   build + publish + read back, run by CI\n"
        "    <language>/...          the real project\n"
        "\n"
        "## Fixtures\n"
        "\n" + listing + "\n"
        "\n"
        "## Regenerating\n"
        "\n"
        "    python3 gen.py .\n"
        "\n"
        "The per-language differences live in one table per ecosystem module, so\n"
        "adding a language is one entry.\n",
    )
    print("generated %d fixture(s): %s" % (len(FIXTURES), " ".join(sorted(FIXTURES))))


if __name__ == "__main__":
    main()
