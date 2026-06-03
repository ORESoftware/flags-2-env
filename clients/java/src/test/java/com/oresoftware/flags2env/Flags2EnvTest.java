package com.oresoftware.flags2env;

import java.util.Map;

public final class Flags2EnvTest {
  public static void main(String[] args) {
    Map<String, String> parsed = Flags2Env.parse(new String[] {"app", "--debug=t", "--port", "8181"});
    if (!"true".equals(parsed.get("DEBUG")) || !"8181".equals(parsed.get("PORT")) || !"true".equals(parsed.get("COLOR"))) {
      throw new AssertionError("unexpected parsed map: " + parsed);
    }
  }
}
