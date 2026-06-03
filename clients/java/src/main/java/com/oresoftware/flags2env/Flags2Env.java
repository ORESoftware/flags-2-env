package com.oresoftware.flags2env;

import java.util.HashMap;
import java.util.Map;

public final class Flags2Env {
  static {
    System.loadLibrary("flags2env_jni");
  }

  private Flags2Env() {}

  public static Map<String, String> parseProcess() {
    return parseJsonObject(parseProcessDefaultJson());
  }

  public static Map<String, String> parseProcess(String configPath) {
    return parseJsonObject(parseProcessJson(configPath));
  }

  public static Map<String, String> parse(String[] argv) {
    return parseJsonObject(parseDefaultJson(argv));
  }

  public static Map<String, String> parse(String configPath, String[] argv) {
    return parseJsonObject(parseJson(configPath, argv));
  }

  public static Map<String, String> applyProcess(Map<String, String> env) {
    Map<String, String> combined = new HashMap<>(env);
    combined.putAll(parseProcess());
    return combined;
  }

  public static Map<String, String> apply(String[] argv, Map<String, String> env) {
    Map<String, String> combined = new HashMap<>(env);
    combined.putAll(parse(argv));
    return combined;
  }

  private static native String parseProcessJson(String configPath);

  private static native String parseProcessDefaultJson();

  private static native String parseJson(String configPath, String[] argv);

  private static native String parseDefaultJson(String[] argv);

  private static Map<String, String> parseJsonObject(String json) {
    JsonCursor cursor = new JsonCursor(json == null ? "{}" : json);
    Map<String, String> out = new HashMap<>();
    cursor.skipWhitespace();
    if (!cursor.consume('{')) {
      return out;
    }

    while (!cursor.done()) {
      cursor.skipWhitespace();
      if (cursor.consume('}')) {
        return out;
      }
      String key = cursor.readString();
      cursor.skipWhitespace();
      if (!cursor.consume(':')) {
        return out;
      }
      String value = cursor.readString();
      out.put(key, value);
      cursor.skipWhitespace();
      if (cursor.consume(',')) {
        continue;
      }
      cursor.consume('}');
      return out;
    }
    return out;
  }

  private static final class JsonCursor {
    private final String value;
    private int index;

    JsonCursor(String value) {
      this.value = value;
      this.index = 0;
    }

    boolean done() {
      return index >= value.length();
    }

    void skipWhitespace() {
      while (!done() && Character.isWhitespace(value.charAt(index))) {
        index++;
      }
    }

    boolean consume(char expected) {
      skipWhitespace();
      if (!done() && value.charAt(index) == expected) {
        index++;
        return true;
      }
      return false;
    }

    String readString() {
      skipWhitespace();
      if (done() || value.charAt(index) != '"') {
        return "";
      }
      index++;
      StringBuilder out = new StringBuilder();
      while (!done()) {
        char ch = value.charAt(index++);
        if (ch == '"') {
          return out.toString();
        }
        if (ch == '\\' && !done()) {
          char escaped = value.charAt(index++);
          switch (escaped) {
            case 'b':
              out.append('\b');
              break;
            case 'f':
              out.append('\f');
              break;
            case 'n':
              out.append('\n');
              break;
            case 'r':
              out.append('\r');
              break;
            case 't':
              out.append('\t');
              break;
            case 'u':
              if (index + 4 <= value.length()) {
                out.append('?');
                index += 4;
              }
              break;
            default:
              out.append(escaped);
              break;
          }
        } else {
          out.append(ch);
        }
      }
      return out.toString();
    }
  }
}
