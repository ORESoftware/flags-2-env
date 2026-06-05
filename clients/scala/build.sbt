import xerial.sbt.Sonatype.sonatypeCentralHost

ThisBuild / organization := "com.oresoftware"
ThisBuild / version := "0.1.0"
ThisBuild / scalaVersion := "2.13.14"
ThisBuild / resolvers += Resolver.mavenLocal
ThisBuild / sonatypeCredentialHost := sonatypeCentralHost
ThisBuild / publishTo := sonatypePublishToBundle.value
ThisBuild / licenses := Seq("MIT" -> url("https://opensource.org/license/mit"))
ThisBuild / homepage := Some(url("https://github.com/ORESoftware/flags-2-env"))
ThisBuild / scmInfo := Some(ScmInfo(url("https://github.com/ORESoftware/flags-2-env"), "scm:git:https://github.com/ORESoftware/flags-2-env.git"))
ThisBuild / developers := List(Developer("oresoftware", "ORESoftware", "", url("https://github.com/ORESoftware")))

lazy val root = (project in file("."))
  .settings(
    name := "flags2env-scala",
    libraryDependencies += "com.oresoftware" % "flags2env" % "0.1.0",
    Compile / packageSrc / publishArtifact := true,
    Compile / packageDoc / publishArtifact := true,
    publishMavenStyle := true
  )
