"""Java, Maven, Gradle/SBT and Ivy fixtures."""

POM = """<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>dev.easyblobs.test</groupId>
  <artifactId>hello</artifactId>
  <version>1.0.0</version>
  <packaging>jar</packaging>
  <properties>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
    <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
  </properties>
</project>
"""

GREETER = """package dev.easyblobs.test.hello;

/** A real class the compiler must accept. */
public final class Greeter {
    private Greeter() {}

    public static String greet(String name) {
        return "hello " + name;
    }
}
"""

MAIN = """package dev.easyblobs.test.hello;

public final class Main {
    private Main() {}

    public static void main(String[] args) {
        System.out.println(Greeter.greet("easyblobs"));
    }
}
"""

# gradle and sbt publish under their own GROUP so their artefacts do not collide
# with maven's: all three go through the same maven adapter, and the mirror keys
# an artefact by group/artifact/version.
GREETER_GRADLE = GREETER.replace(
    "package dev.easyblobs.test.hello;", "package dev.easyblobs.test.gradle;")
MAIN_GRADLE = MAIN.replace(
    "package dev.easyblobs.test.hello;", "package dev.easyblobs.test.gradle;")
GREETER_SBT = GREETER.replace(
    "package dev.easyblobs.test.hello;", "package dev.easyblobs.test.sbt;")


def register(fixture):
    fixture(
        "java",
        {
            "pom.xml": POM,
            "src/main/java/dev/easyblobs/test/hello/Greeter.java": GREETER,
            "src/main/java/dev/easyblobs/test/hello/Main.java": MAIN,
        },
        """#!/bin/sh
# maven: compile, run the jar, then publish it to the mount and read it back.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD: compiles the sources and produces target/hello-1.0.0.jar.
mvn -B -q package
jar=$(ls target/hello-*.jar | head -1)
[ -s "$jar" ] || { echo "maven: no jar produced" >&2; exit 1; }

# RUN it, so a broken class fails here rather than in production.
java -cp "$jar" dev.easyblobs.test.hello.Main

# PUBLISH the jar through the mount.
code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \\
  "$EASYBLOBS_BASE/dev/easyblobs/test/hello/1.0.0/hello-1.0.0.jar" \\
  --data-binary "@$jar")
case "$code" in 200|201) ;; *) echo "maven: PUT jar -> $code" >&2; exit 1 ;; esac

# READ BACK byte-for-byte: a mirror returning 200 with other bytes is broken.
curl -fsS -o /tmp/back.jar "$EASYBLOBS_BASE/dev/easyblobs/test/hello/1.0.0/hello-1.0.0.jar"
cmp -s /tmp/back.jar "$jar" || { echo "maven: bytes changed in the mirror" >&2; exit 1; }
echo "maven: built, ran and published hello-1.0.0.jar (bytes verified)"
""",
        "`mvn package` compiles a real class, the jar is executed, then the jar is "
        "PUT to the mount and read back to compare bytes.\n",
    )

    fixture(
        "gradle",
        {
            "build.gradle": """plugins {
    id 'java'
}

# Distinct coordinates from the maven fixture: several protocols share the
# maven ADAPTER, and two fixtures publishing dev.easyblobs.test:hello:1.0.0
# would overwrite each other's jar in the mirror - the second would look like a
# successful publish while silently replacing the first.
group = 'dev.easyblobs.test.gradle'
version = '1.0.0'

java {
    sourceCompatibility = JavaVersion.VERSION_17
}

repositories {
    // Point gradle at the mount: this is the whole point of the fixture.
    maven {
        url = uri(System.getenv('EASYBLOBS_BASE') ?: 'http://127.0.0.1:8080/artifacts/maven')
        allowInsecureProtocol = true
    }
}
""",
            "settings.gradle": "rootProject.name = 'hello'\n",
            "src/main/java/dev/easyblobs/test/gradle/Greeter.java": GREETER_GRADLE,
            "src/main/java/dev/easyblobs/test/gradle/Main.java": MAIN_GRADLE,
        },
        """#!/bin/sh
# gradle: a real gradle build, using the mount as its maven repository.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD with gradle itself (not mvn): this is what the fixture is for.
gradle --no-daemon --quiet build
jar=$(ls build/libs/*.jar | head -1)
[ -s "$jar" ] || { echo "gradle: no jar produced" >&2; exit 1; }

# gradle, because the fixture is about gradle: running the JAR it produced is the
# assertion that the build really worked.
java -cp "$jar" dev.easyblobs.test.gradle.Main

# PUBLISH the jar to the mount: a build that never reaches the registry does not
# test the registry. The coordinate matches THIS project's group, so it cannot
# overwrite maven's dev.easyblobs.test:hello.
url="$EASYBLOBS_BASE/dev/easyblobs/test/gradle/hello/1.0.0/hello-1.0.0.jar"
code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT "$url" --data-binary "@$jar")
case "$code" in 200|201) ;; *) echo "gradle: PUT jar -> $code" >&2; exit 1 ;; esac

# READ BACK byte-for-byte.
curl -fsS -o /tmp/gradle-back.jar "$url"
cmp -s /tmp/gradle-back.jar "$jar" || {
  echo "gradle: bytes changed in the mirror" >&2; exit 1; }
echo "gradle: built, ran and published hello-1.0.0.jar (bytes verified)"
""",
        "Runs a real Gradle build whose repository is the mount, then executes the "
        "jar it produced.\n",
    )

    fixture(
        "sbt",
        {
            "build.sbt": """scalaVersion := "2.13.14"
name := "easyblobs-test-hello"
// Its own organisation: sbt, gradle and maven all publish through the same maven
// adapter, so a shared coordinate would make each overwrite the previous one.
organization := "dev.easyblobs.test.sbt"
version := "1.0.0"
""",
            "project/build.properties": "sbt.version=1.10.7\n",
            "project/plugins.sbt": """resolvers += Resolver.url(
  "easyblobs-ivy",
  url(sys.env.getOrElse("EASYBLOBS_BASE", "http://127.0.0.1:8080/artifacts/ivy") + "/")
)(Resolver.ivyStylePatterns)
""",
            "src/main/scala/Main.scala": """object Main extends App {
  def greet(name: String): String = s"hello $name"
  println(greet("easyblobs"))
}
""",
        },
        """#!/bin/sh
# sbt: a real sbt build that resolves through the mirrored Ivy repository.
set -eu
: "${EASYBLOBS_BASE:?EASYBLOBS_BASE not set}"

# BUILD with sbt itself; the resolvers point at the mount.
sbt -batch -Dsbt.log.noformat=true compile 2>&1 | tail -5

out=$(find target -name '*.class' | head -1)
[ -n "$out" ] || { echo "sbt: compilation produced no classes" >&2; exit 1; }

# PACKAGE + PUBLISH the compiled output as a jar, then read it back.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
( cd target && zip -qr "$TMP/hello-1.0.0.jar" . )
jar="$TMP/hello-1.0.0.jar"
# sbt's own organisation, so this jar cannot collide with maven's or gradle's.
code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \\
  "$EASYBLOBS_BASE/dev/easyblobs/test/sbt/hello/1.0.0/hello-1.0.0.jar" \\
  --data-binary "@$jar")
case "$code" in 200|201) ;; *) echo "sbt: upload -> $code" >&2; exit 1 ;; esac
curl -fsS -o /tmp/sbt-back.jar \\
  "$EASYBLOBS_BASE/dev/easyblobs/test/sbt/hello/1.0.0/hello-1.0.0.jar"
cmp -s /tmp/sbt-back.jar "$jar" || {
  echo "sbt: the served jar differs" >&2; exit 1; }
echo "sbt: compiled, packaged, published and re-read the jar (bytes verified)"
""",
        "Compiles a real Scala project with sbt, whose resolvers point at the "
        "mirrored Ivy repository.\n",
    )
