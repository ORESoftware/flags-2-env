package com.oresoftware.flags2env.kotlin

import com.oresoftware.flags2env.Flags2Env as JavaFlags2Env

object Flags2Env {
    @JvmStatic
    fun parse(argv: List<String>, configPath: String? = null): Map<String, String> {
        val items = argv.map { it.toString() }.toTypedArray()
        return if (configPath == null) JavaFlags2Env.parse(items) else JavaFlags2Env.parse(configPath, items)
    }

    @JvmStatic
    fun parseProcess(configPath: String? = null): Map<String, String> {
        return if (configPath == null) JavaFlags2Env.parseProcess() else JavaFlags2Env.parseProcess(configPath)
    }

    @JvmStatic
    fun apply(env: Map<String, String>, argv: List<String>, configPath: String? = null): Map<String, String> {
        return env + parse(argv, configPath)
    }

    @JvmStatic
    fun applyProcess(env: Map<String, String>, configPath: String? = null): Map<String, String> {
        return env + parseProcess(configPath)
    }
}
