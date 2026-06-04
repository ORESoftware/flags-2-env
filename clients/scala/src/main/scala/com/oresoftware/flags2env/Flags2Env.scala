package com.oresoftware.flags2env.scala

import com.oresoftware.flags2env.{Flags2Env => JavaFlags2Env}
import scala.jdk.CollectionConverters._

object Flags2Env {
  def parse(argv: Seq[String], configPath: Option[String] = None): Map[String, String] = {
    val items = argv.map(_.toString).toArray
    val parsed = configPath match {
      case Some(path) => JavaFlags2Env.parse(path, items)
      case None => JavaFlags2Env.parse(items)
    }
    parsed.asScala.toMap
  }

  def parseProcess(configPath: Option[String] = None): Map[String, String] = {
    val parsed = configPath match {
      case Some(path) => JavaFlags2Env.parseProcess(path)
      case None => JavaFlags2Env.parseProcess()
    }
    parsed.asScala.toMap
  }

  def apply(env: Map[String, String], argv: Seq[String], configPath: Option[String] = None): Map[String, String] =
    env ++ parse(argv, configPath)

  def applyProcess(env: Map[String, String], configPath: Option[String] = None): Map[String, String] =
    env ++ parseProcess(configPath)
}
