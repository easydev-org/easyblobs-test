# easyblobs-test

Real, buildable fixtures for every language/toolchain that easyblobs
mirrors.

A test suite CLONES this repo and runs the real toolchain against
easyblobs - build, publish, read back - instead of writing throwaway
files inside each test script. When a fixture builds and publishes here
the toolchain works; when it does not, the failure is in the toolchain or
the protocol, never in a hand-written stub.

## Layout

    <language>/README.md    what this fixture proves
    <language>/publish.sh   build + publish + read back, run by CI
    <language>/...          the real project

## Fixtures

- `bazel`
- `buf`
- `conda`
- `deno`
- `dotnet`
- `elixir`
- `erlang`
- `go`
- `gradle`
- `helm`
- `java`
- `julia`
- `node`
- `perl`
- `php`
- `python`
- `r`
- `ruby`
- `rust`
- `sbt`
- `swift`

## Regenerating

    python3 gen.py .

The per-language differences live in one table per ecosystem module, so
adding a language is one entry.
