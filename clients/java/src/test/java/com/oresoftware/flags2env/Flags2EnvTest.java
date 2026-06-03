package com.oresoftware.flags2env;

import java.util.HashMap;
import java.util.Map;

public final class Flags2EnvTest {
  public static void main(String[] args) {
    Map<String, String> parsed = Flags2Env.parse(new String[] {"app", "--debug=t", "--port", "8181"});
    if (!"true".equals(parsed.get("DEBUG")) || !"8181".equals(parsed.get("PORT")) || !"true".equals(parsed.get("COLOR"))) {
      throw new AssertionError("unexpected parsed map: " + parsed);
    }

    Map<String, String> explicit = Flags2Env.parse("../../.cli-flags.toml", new String[] {"app", "--debug=f"});
    if (!"false".equals(explicit.get("DEBUG")) || !"3000".equals(explicit.get("PORT"))) {
      throw new AssertionError("unexpected explicit config map: " + explicit);
    }

    Map<String, String> env = new HashMap<>();
    env.put("PORT", "env");
    env.put("KEEP", "1");
    Map<String, String> combined = Flags2Env.apply(new String[] {"app", "--port", "8181"}, env);
    if (!"8181".equals(combined.get("PORT")) || !"1".equals(combined.get("KEEP")) || !"true".equals(combined.get("COLOR"))) {
      throw new AssertionError("unexpected combined map: " + combined);
    }
  }
}
