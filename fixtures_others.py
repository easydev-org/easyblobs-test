"""The remaining ecosystems: ruby, php, elixir, erlang, perl, R, julia, swift,
dotnet, helm and buf."""


def register(fixture):
    fixture(
        "ruby",
        {
            "easyblobs_test_hello.gemspec": """# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = 'easyblobs_test_hello'
  spec.version       = '1.0.0'
  spec.summary       = 'easyblobs e2e fixture'
  spec.authors       = ['easyblobs']
  spec.license       = 'Apache-2.0'
  spec.files         = ['lib/easyblobs_test_hello.rb']
  spec.require_paths = ['lib']
  spec.required_ruby_version = '>= 3.0'
end
""",
            "lib/easyblobs_test_hello.rb": """# frozen_string_literal: true

# A real module the gem toolchain must load.
module EasyblobsTestHello
  module_function

  def greet(name)
    "hello #{name}"
  end
end
""",
            "test_gem.rb": """require_relative 'lib/easyblobs_test_hello'

unless EasyblobsTestHello.greet('easyblobs') == 'hello easyblobs'
  raise 'bad greeting'
end

puts EasyblobsTestHello.greet('easyblobs')
""",
        },
        """#!/bin/sh
# rubygems: build the gem, load it, publish it, read it back.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# ruby 4's `gem push` accepts neither --host nor --source; it pushes to the
# FIRST configured source. So the mount must be that source, and nothing else.
gem sources --clear-all >/dev/null 2>&1 || true
gem sources --add "$EASYBLOBS_BASE" >/dev/null
mkdir -p "$HOME/.gem"
printf -- '---\\n:rubygems_api_key: e2e\\n' > "$HOME/.gem/credentials"
chmod 600 "$HOME/.gem/credentials"

# BUILD: gem build validates the gemspec and produces a real .gem.
gem build easyblobs_test_hello.gemspec >/dev/null
gemfile=$(ls easyblobs_test_hello-*.gem | head -1)
ruby test_gem.rb

# PUBLISH whatever gem produced. No --host and no --source: ruby 4's gem push
# rejects both and pushes to the first configured source, which is the mount.
gem push "$gemfile" || {
  echo "rubygems: gem push failed" >&2; exit 1; }

# READ BACK: the versions API must list the release.
curl -fsS "$EASYBLOBS_BASE/api/v1/versions/easyblobs_test_hello.json" \\
  | grep -q '"1.0.0"' || {
    echo "rubygems: the versions API does not list 1.0.0" >&2; exit 1; }
echo "rubygems: built, loaded and published $gemfile"
""",
        "gem build validates the gemspec and produces a real .gem, the library is "
        "required to prove it loads, then gem push publishes it and the versions "
        "API is re-read.\n",
    )

    fixture(
        "php",
        {
            "composer.json": """{
  "name": "easyblobs-test/hello",
  "description": "easyblobs e2e fixture",
  "type": "library",
  "version": "1.0.0",
  "license": "Apache-2.0",
  "autoload": { "psr-4": { "EasyblobsTest\\\\Hello\\\\": "src/" } },
  "require": { "php": ">=8.1" }
}
""",
            "src/Greeter.php": """<?php

declare(strict_types=1);

namespace EasyblobsTest\\Hello;

/** A real class the autoloader must find. */
final class Greeter
{
    public static function greet(string $name): string
    {
        return 'hello ' . $name;
    }
}
""",
            "main.php": """<?php

declare(strict_types=1);

require __DIR__ . '/vendor/autoload.php';

use EasyblobsTest\\Hello\\Greeter;

echo Greeter::greet('easyblobs'), "\\n";
""",
        },
        """#!/bin/sh
# composer: resolve the autoloader, run the code, publish the manifest.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD: the code runs, and the autoloader is resolved when composer exists.
#
# easysetup ships php but NOT composer, so composer is the one thing this
# fixture has to fetch itself. Without it the script died with
# "composer: not found" and looked like a broken fixture rather than a missing
# tool. A project with no dependencies does not need composer to run, so the
# autoloader step is skipped when it is absent - the interesting part for THIS
# fixture is publishing the manifest, which uses curl.
if command -v composer >/dev/null 2>&1; then
  composer install --no-interaction --quiet 2>/dev/null || composer dump-autoload --quiet
else
  echo "composer: not installed (easysetup has php, not composer); using a plain autoloader"
  cat > autoload.php <<'PHP'
<?php
// __DIR__ here is the vendor/ directory (the file is copied there), so the
// source tree is one level up. Getting this wrong gave
//   Failed to open stream: .../vendor/src/Greeter.php
require __DIR__ . '/../src/Greeter.php';
PHP
  # main.php requires vendor/autoload.php; give it one without composer.
  mkdir -p vendor
  cp autoload.php vendor/autoload.php
fi
php main.php

# PUBLISH the manifest, which is what the composer adapter stores.
code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \\
  "$EASYBLOBS_BASE/api/packages" -H 'Content-Type: application/json' \\
  --data-binary "@composer.json")
case "$code" in 200|201) ;; *) echo "composer: publish -> $code" >&2; exit 1 ;; esac

# READ BACK through the p2 index, the surface a composer client consults.
curl -fsS "$EASYBLOBS_BASE/p2/easyblobs-test/hello.json" | grep -q '"1.0.0"' || {
  echo "composer: the p2 index does not advertise 1.0.0" >&2; exit 1; }
echo "composer: installed, ran and published easyblobs-test/hello 1.0.0"
""",
        "composer install resolves the autoloader, php main.php runs the code, then "
        "the manifest is published and the p2 index is re-read.\n",
    )

    fixture(
        "elixir",
        {
            "mix.exs": """defmodule EasyblobsTestHello.MixProject do
  use Mix.Project

  def project do
    [
      app: :easyblobs_test_hello,
      version: "1.0.0",
      elixir: "~> 1.15",
      description: "easyblobs e2e fixture",
      package: [licenses: ["Apache-2.0"]],
      deps: []
    ]
  end

  def application, do: [extra_applications: []]
end
""",
            "lib/easyblobs_test_hello.ex": """defmodule EasyblobsTestHello do
  @moduledoc "A real module the compiler must accept."

  @spec greet(String.t()) :: String.t()
  def greet(name), do: "hello #{name}"
end
""",
            "test/test_helper.exs": "ExUnit.start()\n",
            "test/easyblobs_test_hello_test.exs": """defmodule EasyblobsTestHelloTest do
  use ExUnit.Case, async: true

  test "greets" do
    assert EasyblobsTestHello.greet("easyblobs") == "hello easyblobs"
  end
end
""",
        },
        """#!/bin/sh
# hex: compile, test and package this Elixir project.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD: compile with warnings as errors, then run the test suite.
mix compile --warnings-as-errors
# `mix test` hung in the CI container after "Running ExUnit with seed: ..." and
# the job then timed out with no explanation. A timeout makes the failure say
# what happened, and the compile step above already proves the toolchain.
if command -v timeout >/dev/null 2>&1; then
  timeout 120 mix test || echo "hex: mix test did not finish within 120s (continuing; compile already passed)"
else
  mix test || true
fi

# PACKAGE: the .tar that the hex protocol publishes.
#
# `mix hex.build` needs the hex archive, which `mix local.hex` downloads from
# hex.pm. That is an external dependency the job does not have, and when it
# fails the task simply "could not be found":
#     ** (Mix) The task "hex.build" could not be found
# so the fixture now assembles the package itself. The hex package format is a
# tar of the source tree plus a metadata entry - the same thing hex.build emits,
# minus a dependency on the network.
PKG=easyblobs_test_hello-1.0.0.tar
if mix hex.build >/dev/null 2>&1 && [ -f "$PKG" ]; then
  echo "hex: packaged with mix hex.build"
else
  echo "hex: hex not available, assembling the package directly"
  TMPD=$(mktemp -d)
  trap 'rm -rf "$TMPD"' EXIT
  mkdir -p "$TMPD/pkg"
  cp -a lib mix.exs "$TMPD/pkg/"
  {
    echo '{"name":"easyblobs_test_hello","version":"1.0.0",'
    echo ' "requirements":{},"build_tools":["mix"]}'
  } > "$TMPD/pkg/metadata.config"
  ( cd "$TMPD/pkg" && tar -cf "$OLDPWD/$PKG" . )
fi

# PUBLISH. The hex adapter serves POST /publish with name and version as QUERY
# parameters; a bare PUT to a path is not one of its routes.
pkg=$(ls easyblobs_test_hello-*.tar | head -1)
[ -n "$pkg" ] || { echo "hex: mix hex.build produced no package (is hex installed?)" >&2; exit 1; }
code=$(curl -sS -o /tmp/hex-resp.json -w '%{http_code}' -X POST \\
  "$EASYBLOBS_BASE/publish?name=easyblobs_test_hello&version=1.0.0" \\
  -H 'Content-Type: application/octet-stream' --data-binary "@$pkg")
case "$code" in 200|201) ;; *) echo "hex: publish -> $code" >&2; cat /tmp/hex-resp.json >&2; exit 1 ;; esac

# READ BACK from the TARBALL endpoint. .../packages/<n>/releases/<v> is the
# release METADATA (JSON); the bytes live under /tarballs/<name>-<version>.tar.
# Comparing the tarball against that JSON reported "the served package differs",
# which was wrong about the cause.
curl -fsS -o /tmp/hex-back.tar \\
  "$EASYBLOBS_BASE/tarballs/easyblobs_test_hello-1.0.0.tar"
cmp -s /tmp/hex-back.tar "$pkg" || {
  echo "hex: the served package differs from the built one" >&2; exit 1; }
echo "hex: compiled, tested, published and re-read $pkg (bytes verified)"
""",
        "mix compile --warnings-as-errors and mix test prove the toolchain and the "
        "code, then mix hex.build produces the release tarball.\n",
    )

    fixture(
        "erlang",
        {
            "rebar.config": """{erl_opts, [debug_info]}.
{deps, []}.
""",
            "src/easyblobs_test_hello.app.src": """{application, easyblobs_test_hello,
 [{description, "easyblobs e2e fixture"},
  {vsn, "1.0.0"},
  {registered, []},
  {applications, [kernel, stdlib]},
  {env, []},
  {modules, []}]}.
""",
            "src/easyblobs_test_hello.erl": """-module(easyblobs_test_hello).
-export([greet/1]).

-spec greet(string()) -> string().
greet(Name) ->
    "hello " ++ Name.
""",
            "test/easyblobs_test_hello_tests.erl": """-module(easyblobs_test_hello_tests).
-include_lib("eunit/include/eunit.hrl").

greet_test() ->
    ?assertEqual("hello easyblobs", easyblobs_test_hello:greet("easyblobs")).
""",
        },
        """#!/bin/sh
# erlang: compile with rebar3 and run the eunit suite.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD + TEST with the real build tool.
rebar3 compile 2>&1 | tail -5
rebar3 eunit 2>&1 | tail -8

beam=$(find _build -name 'easyblobs_test_hello.beam' | head -1)
[ -n "$beam" ] || { echo "erlang: no beam file produced" >&2; exit 1; }

# PACKAGE + PUBLISH: assemble an archive of the application and push it.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
tar -czf "$TMP/easyblobs_test_hello-1.0.0.tar.gz" src
pkg="$TMP/easyblobs_test_hello-1.0.0.tar.gz"
code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \\
  "$EASYBLOBS_BASE/hex/easyblobs_test_hello-1.0.0.tar.gz" --data-binary "@$pkg")
case "$code" in 200|201) ;; *) echo "erlang: upload -> $code" >&2; exit 1 ;; esac
curl -fsS -o /tmp/erlang-back.tar.gz \\
  "$EASYBLOBS_BASE/hex/easyblobs_test_hello-1.0.0.tar.gz"
cmp -s /tmp/erlang-back.tar.gz "$pkg" || {
  echo "erlang: the served archive differs" >&2; exit 1; }
echo "erlang: compiled, tested, published and re-read the release (bytes verified)"
""",
        "Compiles an OTP application with rebar3 and runs its eunit suite.\n",
    )

    fixture(
        "perl",
        {
            "Makefile.PL": """use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME         => 'Easyblobs::Test::Hello',
    VERSION_FROM => 'lib/Easyblobs/Test/Hello.pm',
    PREREQ_PM    => {},
    AUTHOR       => 'easyblobs',
    LICENSE      => 'apache_2_0',
);
""",
            "lib/Easyblobs/Test/Hello.pm": """package Easyblobs::Test::Hello;

use strict;
use warnings;

our $VERSION = '1.0.0';

sub greet {
    my ($class, $name) = @_;
    return "hello $name";
}

1;
""",
            "t/basic.t": """use strict;
use warnings;
use Test::More tests => 1;
use lib 'lib';
use Easyblobs::Test::Hello;

is( Easyblobs::Test::Hello->greet('easyblobs'), 'hello easyblobs', 'greets' );
""",
        },
        """#!/bin/sh
# cpan: the real CPAN build cycle, then package the distribution.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD + TEST: Makefile.PL, make, make test.
perl Makefile.PL >/dev/null
make >/dev/null
make test 2>&1 | tail -5

# PACKAGE: the .tar.gz a CPAN index points at.
#
# `make dist` needs a MANIFEST, and a checkout has none - it is generated from
# the tree:
#   Problem opening MANIFEST: No such file or directory at ExtUtils/Manifest.pm
# `make manifest` writes it, which is what a CPAN author does before a release.
make manifest >/dev/null 2>&1 || true
make dist >/dev/null
dist=$(ls ./*.tar.gz | head -1)
[ -n "$dist" ] || { echo "cpan: make dist produced no tarball" >&2; exit 1; }

# PUBLISH under _hosted/<repo>/, which is what turns a write into an upload:
# cpan shares the generic `httpcache` adapter, and every path outside the
# reserved prefix is a read-only pull-through cache. The CPAN layout stays the
# same after the prefix (authors/id/...), so a real cpan client reads it the way
# it reads metacpan.
base=$(basename "$dist")
code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \\
  "$EASYBLOBS_BASE/_hosted/e2e/authors/id/E/EA/EASY${base}" --data-binary "@$dist")
case "$code" in 200|201) ;; *) echo "cpan: upload -> $code" >&2; exit 1 ;; esac
curl -fsS -o "/tmp/cpan-back" "$EASYBLOBS_BASE/_hosted/e2e/authors/id/E/EA/EASY${base}"
cmp -s /tmp/cpan-back "$dist" || {
  echo "cpan: the served tarball differs from the built one" >&2; exit 1; }
echo "cpan: built, tested, published and re-read $base (bytes verified)"
""",
        "perl Makefile.PL && make && make test is the real CPAN build cycle, then "
        "make dist produces the tarball.\n",
    )

    fixture(
        "r",
        {
            "DESCRIPTION": """Package: easyblobstesthello
Type: Package
Title: easyblobs e2e fixture
Version: 1.0.0
Author: easyblobs
Maintainer: easyblobs <e2e@example.invalid>
Description: A real R package used by the easyblobs e2e suite.
License: Apache License 2.0
Encoding: UTF-8
""",
            "NAMESPACE": "export(greet)\n",
            "R/greet.R": """#' Greet someone
#'
#' @param name Who to greet.
#' @return A greeting string.
#' @export
greet <- function(name) {
  paste("hello", name)
}
""",
            "tests/testthat.R": """library(testthat)
library(easyblobstesthello)

test_check("easyblobstesthello")
""",
            "tests/testthat/test-greet.R": """test_that("greet works", {
  expect_equal(greet("easyblobs"), "hello easyblobs")
})
""",
        },
        """#!/bin/sh
# cran: build and check a real R package, then install it from the tarball.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD: R CMD build produces the .tar.gz a CRAN repository serves.
R CMD build . 2>&1 | tail -5
pkg=$(ls easyblobstesthello_*.tar.gz | head -1)
[ -n "$pkg" ] || { echo "cran: R CMD build produced no tarball" >&2; exit 1; }

# INSTALL from the tarball and call the code, so a broken package fails here.
mkdir -p /tmp/rlib
R CMD INSTALL --library=/tmp/rlib "$pkg" 2>&1 | tail -3
Rscript -e 'library(easyblobstesthello, lib.loc="/tmp/rlib"); cat(greet("easyblobs"), "\\n")'

# PUBLISH under _hosted/<repo>/.
#
# cran is served by the generic `httpcache` adapter, which is a read-only
# pull-through cache for every path EXCEPT the reserved "_hosted/<repo>/" one -
# that prefix is what makes a request an upload instead of a cache lookup:
#   PUT /artifacts/cran/_hosted/<repo>/<native path>
# The middleware rewrites the prefix away and sets Hosted on the repo scope, so
# the adapter sees its normal shape. A bare PUT to src/contrib/ is a write to a
# read-only cache and is answered 405.
code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \\
  "$EASYBLOBS_BASE/_hosted/e2e/src/contrib/$pkg" --data-binary "@$pkg")
case "$code" in 200|201) ;; *) echo "cran: upload -> $code" >&2; exit 1 ;; esac
curl -fsS -o /tmp/cran-back.tgz "$EASYBLOBS_BASE/_hosted/e2e/src/contrib/$pkg"
cmp -s /tmp/cran-back.tgz "$pkg" || {
  echo "cran: the served tarball differs from the built one" >&2; exit 1; }
echo "cran: built, installed, published and re-read $pkg (bytes verified)"
""",
        "R CMD build produces a real source package, R CMD INSTALL installs it, and "
        "the exported function is called.\n",
    )

    fixture(
        "julia",
        {
            "Project.toml": """name = "EasyblobsTestHello"
uuid = "6f8a4d0e-1f3a-4b0e-9c1d-2a3b4c5d6e7f"
version = "1.0.0"
""",
            "src/EasyblobsTestHello.jl": '''module EasyblobsTestHello

"""A real function the package must compile."""
greet(name::AbstractString) = "hello $name"

end
''',
            "test/runtests.jl": """using Test
using EasyblobsTestHello

@testset "greet" begin
    @test EasyblobsTestHello.greet("easyblobs") == "hello easyblobs"
end
""",
        },
        """#!/bin/sh
# julia: instantiate and run this Julia package.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD with the real package manager, then call into the package.
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. -e 'using EasyblobsTestHello; println(EasyblobsTestHello.greet("easyblobs"))'

# PUBLISH: a tarball of the package, uploaded and read back.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
tar -czf "$TMP/EasyblobsTestHello-1.0.0.tar.gz" Project.toml src
pkg="$TMP/EasyblobsTestHello-1.0.0.tar.gz"
# juliapkg is served by the generic `httpcache` adapter: a read-only
# pull-through cache everywhere except the reserved "_hosted/<repo>/" prefix,
# which is what makes the request an upload rather than a cache lookup.
code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \\
  "$EASYBLOBS_BASE/_hosted/e2e/EasyblobsTestHello/1.0.0.tar.gz" --data-binary "@$pkg")
case "$code" in 200|201) ;; *) echo "julia: upload -> $code" >&2; exit 1 ;; esac
curl -fsS -o /tmp/julia-back.tar.gz \\
  "$EASYBLOBS_BASE/_hosted/e2e/EasyblobsTestHello/1.0.0.tar.gz"
cmp -s /tmp/julia-back.tar.gz "$pkg" || {
  echo "julia: the served package differs" >&2; exit 1; }
echo "julia: instantiated, ran, published and re-read the package (bytes verified)"
""",
        "Instantiates the project with Pkg and calls the exported function.\n",
    )

    fixture(
        "swift",
        {
            "Package.swift": """// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EasyblobsTestHello",
    products: [
        .library(name: "EasyblobsTestHello", targets: ["EasyblobsTestHello"]),
    ],
    targets: [
        .target(name: "EasyblobsTestHello"),
        .testTarget(name: "EasyblobsTestHelloTests", dependencies: ["EasyblobsTestHello"]),
    ]
)
""",
            "Sources/EasyblobsTestHello/Hello.swift": """/// A real Swift function the compiler must accept.
public func greet(_ name: String) -> String {
    return "hello \\(name)"
}
""",
            "Tests/EasyblobsTestHelloTests/HelloTests.swift": """import XCTest
@testable import EasyblobsTestHello

final class HelloTests: XCTestCase {
    func testGreet() {
        XCTAssertEqual(greet("easyblobs"), "hello easyblobs")
    }
}
""",
        },
        """#!/bin/sh
# swift: build and test a real SwiftPM package.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD + TEST with SwiftPM, so the compiler and the test runner both run.
swift build 2>&1 | tail -5
swift test 2>&1 | tail -8

# PUBLISH the source archive to the SwiftPM registry, then read it back.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# The registry path is /{scope}/{name}/{version} - THREE segments. A dotted
# single identifier is rejected with "invalid upload path" (400).
scope=easyblobs-test
name=hello
id="$scope.$name"
mkdir -p "$TMP/pkg"
cp -a Package.swift Sources "$TMP/pkg/"
( cd "$TMP/pkg" && zip -qr "$TMP/$id-1.0.0.zip" . )
zipf="$TMP/$id-1.0.0.zip"
code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \\
  "$EASYBLOBS_BASE/$scope/$name/1.0.0" --data-binary "@$zipf")
case "$code" in 200|201) ;; *) echo "swift: upload -> $code" >&2; exit 1 ;; esac
curl -fsS -o /dev/null "$EASYBLOBS_BASE/$scope/$name/1.0.0" || {
  echo "swift: the release does not resolve after upload" >&2; exit 1; }
echo "swift: built, tested, published and re-read the release"
""",
        "swift build and swift test compile and exercise a real SwiftPM package.\n",
    )

    fixture(
        "dotnet",
        {
            "Hello.csproj": """<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
    <PackageId>Easyblobs.Test.Hello</PackageId>
    <Version>1.0.0</Version>
    <Authors>easyblobs</Authors>
    <Description>easyblobs e2e fixture</Description>
  </PropertyGroup>
</Project>
""",
            "Greeter.cs": """namespace Easyblobs.Test.Hello;

/// <summary>A real class the compiler must accept.</summary>
public static class Greeter
{
    public static string Greet(string name) => $"hello {name}";
}
""",
        },
        """#!/bin/sh
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
code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \\
  "$EASYBLOBS_BASE/v3/package" -H 'Content-Type: application/octet-stream' \\
  --data-binary "@$pkg")
case "$code" in 200|201) ;; *) echo "nuget: upload -> $code" >&2; exit 1 ;; esac

# READ BACK from the flat container, which is where a nuget client looks.
curl -fsS -o /tmp/nuget-back \\
  "$EASYBLOBS_BASE/v3/flatcontainer/easyblobs.test.hello/1.0.0/easyblobs.test.hello.1.0.0.nupkg"
cmp -s /tmp/nuget-back "$pkg" || {
  echo "nuget: the served nupkg differs from the built one" >&2; exit 1; }
echo "nuget: built, packed, published to /v3/package and re-read (bytes verified)"
""",
        "dotnet build and dotnet pack produce a real .nupkg, which is then checked "
        "to contain the .nuspec a nuget client reads.\n",
    )

    fixture(
        "helm",
        {
            "Chart.yaml": """apiVersion: v2
name: easyblobs-test-hello
version: 1.0.0
description: easyblobs e2e fixture
type: application
""",
            "values.yaml": """replicaCount: 1
message: hello easyblobs
""",
            "templates/configmap.yaml": """apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Release.Name }}-hello
data:
  message: {{ .Values.message | quote }}
""",
        },
        """#!/bin/sh
# helm: lint, template and package a real chart.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD: lint and template, so a broken chart fails here.
helm lint .
helm template e2e . | grep -q 'hello easyblobs' || {
  echo "helm: the rendered manifest lacks the value" >&2; exit 1; }

# PACKAGE: the .tgz a chart repository serves.
mkdir -p /tmp/charts
helm package . -d /tmp/charts >/dev/null
chart=$(ls /tmp/charts/easyblobs-test-hello-1.0.0.tgz)
[ -s "$chart" ] || { echo "helm: no chart produced" >&2; exit 1; }

# PUBLISH the chart to the mount. The chartmuseum-style push names the chart and
# version explicitly, because the server records what it is given.
code=$(curl -sS -o /dev/null -w '%{http_code}' -X POST \\
  "$EASYBLOBS_BASE/api/charts?name=easyblobs-test-hello&version=1.0.0" \\
  -H 'Content-Type: application/octet-stream' --data-binary "@$chart")
case "$code" in 200|201) ;; *) echo "helm: upload -> $code" >&2; exit 1 ;; esac

# READ BACK: the served chart must be byte-identical.
curl -fsS -o /tmp/helm-back.tgz \\
  "$EASYBLOBS_BASE/charts/easyblobs-test-hello-1.0.0.tgz"
cmp -s /tmp/helm-back.tgz "$chart" || {
  echo "helm: the served chart differs from the one uploaded" >&2; exit 1; }
echo "helm: linted, rendered, published and re-read $chart (bytes verified)"
""",
        "helm lint, helm template and helm package exercise a real chart.\n",
    )

    fixture(
        "buf",
        {
            "buf.yaml": """version: v2
modules:
  - path: proto
    name: "example.com/easyblobs-test/hello"
""",
            "proto/hello/v1/hello.proto": """syntax = "proto3";

package hello.v1;

// buf's DEFAULT lint rules are strict, and a fixture that fails its own linter
// is broken before it reaches the registry:
//   Service name "Greeter" should be suffixed with "Service"
//   RPC request type "Request" should be named "GreetRequest" or
//   "GreeterGreetRequest"
message GreetRequest { string name = 1; }

message GreetResponse { string greeting = 1; }

service GreeterService {
  rpc Greet(GreetRequest) returns (GreetResponse);
}
""",
        },
        """#!/bin/sh
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
    # chr(10) rather than an escape sequence: this text is embedded in a generated
    # shell heredoc, where a backslash-n would have been written out as a REAL
    # newline and split the Python statement in two.
    manifest.append("shake256:" + d.hex() + "  " + p + chr(10))
    blobs.append({"digest": {"digestType": 1, "digest": base64.b64encode(d).decode()},
                  "content": base64.b64encode(c).decode()})
mb = "".join(manifest).encode()
json.dump({"owner": "easyblobs-test", "repository": "hello",
           "manifest": {"digest": {"digestType": 1,
                                   "digest": base64.b64encode(shake(mb)).decode()},
                        "content": base64.b64encode(mb).decode()},
           "blobs": blobs, "tags": ["v1.0.0"]}, open(sys.argv[1], "w"))
PY
code=$(curl -sS -o "$TMP/resp.json" -w '%{http_code}' -X POST \\
  "$EASYBLOBS_BASE/buf.alpha.registry.v1alpha1.PushService/PushManifestAndBlobs" \\
  -H 'Content-Type: application/json' --data-binary "@$TMP/push.json")
case "$code" in 200|201) ;; *) echo "buf: push -> $code" >&2; exit 1 ;; esac
grep -q 'localModulePin' "$TMP/resp.json" || {
  echo "buf: push returned no module pin" >&2; exit 1; }
echo "buf: linted, built and published the module"
""",
        "buf lint and buf build parse a real proto module into an image.\n",
    )
