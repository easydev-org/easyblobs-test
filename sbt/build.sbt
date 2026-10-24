scalaVersion := "2.13.14"
name := "easyblobs-test-hello"
// Its own organisation: sbt, gradle and maven all publish through the same maven
// adapter, so a shared coordinate would make each overwrite the previous one.
organization := "dev.easyblobs.test.sbt"
version := "1.0.0"
