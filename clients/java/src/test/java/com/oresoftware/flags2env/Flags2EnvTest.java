package com.oresoftware.flags2env;

import java.io.IOException;
import java.util.HashMap;
import java.util.Map;
import java.nio.file.Files;
import java.nio.file.Path;

public final class Flags2EnvTest {
  public static void main(String[] args) throws IOException {
    Path config = Files.createTempFile("flags2env-java-smoke", ".toml");
    Files.writeString(config, String.join("\n",
        "[flags.port]",
        "env = \"PORT\"",
        "aliases = [\"port\"]",
        "type = \"integer\"",
        "",
        "[flags.debug]",
        "env = \"DEBUG\"",
        "aliases = [\"debug\"]",
        "type = \"bool\"",
        "true_aliases = [\"t\"]",
        "false_aliases = [\"f\"]",
        ""));

    Map<String, String> parsed = Flags2Env.parse(config.toString(), new String[] {"app", "--debug=t", "--port", "8181"});
    if (!"true".equals(parsed.get("DEBUG")) || !"8181".equals(parsed.get("PORT"))) {
      throw new AssertionError("unexpected parsed map: " + parsed);
    }

    Map<String, String> explicit = Flags2Env.parse(config.toString(), new String[] {"app", "--debug=f"});
    if (!"false".equals(explicit.get("DEBUG"))) {
      throw new AssertionError("unexpected explicit config map: " + explicit);
    }

    Map<String, String> env = new HashMap<>();
    env.put("PORT", "env");
    env.put("KEEP", "1");
    Map<String, String> combined = new HashMap<>(env);
    combined.putAll(Flags2Env.parse(config.toString(), new String[] {"app", "--port", "8181"}));
    if (!"8181".equals(combined.get("PORT")) || !"1".equals(combined.get("KEEP"))) {
      throw new AssertionError("unexpected combined map: " + combined);
    }
  }
}
