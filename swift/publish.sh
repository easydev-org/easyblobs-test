#!/bin/sh
# swift: build and test a real SwiftPM package.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD + TEST with SwiftPM, so the compiler and the test runner both run.
swift build 2>&1 | tail -5
swift test 2>&1 | tail -8
echo "swift: built and tested the package"
