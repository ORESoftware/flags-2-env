package com.oresoftware.flags2env.groovy

class Flags2Env {
  static Map<String, String> parse(List<String> argv, String configPath = null) {
    String[] items = argv.collect { it.toString() } as String[]
    Map<String, String> parsed = configPath == null
      ? com.oresoftware.flags2env.Flags2Env.parse(items)
      : com.oresoftware.flags2env.Flags2Env.parse(configPath, items)
    new LinkedHashMap<String, String>(parsed)
  }

  static Map<String, String> parseProcess(String configPath = null) {
    Map<String, String> parsed = configPath == null
      ? com.oresoftware.flags2env.Flags2Env.parseProcess()
      : com.oresoftware.flags2env.Flags2Env.parseProcess(configPath)
    new LinkedHashMap<String, String>(parsed)
  }

  static Map<String, String> apply(Map<String, String> env, List<String> argv, String configPath = null) {
    Map<String, String> combined = new LinkedHashMap<String, String>(env)
    combined.putAll(parse(argv, configPath))
    combined
  }
}
