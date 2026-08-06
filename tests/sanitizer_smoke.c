#include "parser.h"

#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define DEEP_CONFIG "tests/subcommands-deep/.cli-flags.toml"
#define CODEGEN_CONFIG "tests/codegen/.cli-flags.toml"
#define FIXTURE_CONFIG "tests/fixtures/.cli-flags.toml"
#define ARRAY_LEN(values) (sizeof(values) / sizeof((values)[0]))

static void fail(const char *label, const char *message) {
  fprintf(stderr, "%s: %s\n", label, message);
  exit(1);
}

static int argv_count(const char *label, size_t count) {
  if (count > (size_t)INT_MAX) {
    fail(label, "argv count exceeds INT_MAX");
  }
  return (int)count;
}

static void expect_boolean_result(const char *label, int value) {
  if (value != 0 && value != 1) {
    fail(label, "returned a non-boolean result");
  }
}

static void consume_owned(const char *label, char *value) {
  if (value == NULL) {
    fail(label, "returned NULL");
  }
  if (value[0] == '\0') {
    f2e_free(value);
    fail(label, "returned an empty string");
  }
  f2e_free(value);
}

static void exercise_json_argv_boundaries(void) {
  static const char *const cases[] = {
      "[]",
      "[\"tool\"]",
      "[\"tool\",\"--debug\"]",
      "[\"tool\",\"workspace\",\"remotes\",\"create\",\"annotate\",\"--name\",\"release\"]",
      "[\"tool\",\"--label\",\"workspace\",\"workspace\",\"remotes\",\"create\"]",
      "[\"tool\",\"workspace\",\"--\",\"remotes\",\"create\"]",
      "null",
      "{}",
      "[1,true,null]",
      "[\"unterminated\"",
      "not-json",
  };

  size_t i;
  for (i = 0; i < ARRAY_LEN(cases); ++i) {
    consume_owned("parse_json_argv",
                  f2e_parse_json_argv_from_file(DEEP_CONFIG, cases[i]));
    consume_owned("parse_structured_json_argv",
                  f2e_parse_structured_json_argv_from_file(DEEP_CONFIG, cases[i]));
    consume_owned("resolve_commands_json_argv",
                  f2e_resolve_commands_json_argv_from_file(DEEP_CONFIG, cases[i]));
    expect_boolean_result("help detection",
                          f2e_is_help_requested_json_argv(cases[i]));
  }
}

static void exercise_deep_aliases(void) {
  const char *canonical[] = {
      "tool", "ws", "remote", "add", "tag", "--name", "release", "--dry-run",
  };
  const char *aliases[] = {
      "tool", "workspace", "remotes", "create", "annotate", "--name", "release", "--dry-run",
  };
  const char *alias_as_value[] = {
      "tool", "--label", "workspace", "workspace", "remotes", "create", "annotate", "--name", "create",
  };
  const int canonical_argc = argv_count("canonical argv", ARRAY_LEN(canonical));
  const int aliases_argc = argv_count("aliases argv", ARRAY_LEN(aliases));
  const int alias_as_value_argc = argv_count("alias-as-value argv", ARRAY_LEN(alias_as_value));

  consume_owned("parse canonical deep command",
                f2e_parse_structured_from_file(DEEP_CONFIG, canonical_argc, canonical));
  consume_owned("parse aliased deep command",
                f2e_parse_structured_from_file(DEEP_CONFIG, aliases_argc, aliases));
  consume_owned("resolve canonical deep command",
                f2e_resolve_commands_from_file(DEEP_CONFIG, canonical_argc, canonical));
  consume_owned("resolve aliased deep command",
                f2e_resolve_commands_from_file(DEEP_CONFIG, aliases_argc, aliases));
  consume_owned("alias token remains an option value",
                f2e_parse_structured_from_file(DEEP_CONFIG, alias_as_value_argc, alias_as_value));
  consume_owned("deep help through aliases",
                f2e_help_table_for_argv_from_file(DEEP_CONFIG, "tool", aliases_argc, aliases, 100));
  consume_owned("bash completion", f2e_completion_script_from_file(DEEP_CONFIG, "bash", "tool"));
  consume_owned("zsh completion", f2e_completion_script_from_file(DEEP_CONFIG, "zsh", "tool"));
  consume_owned("deep config audit", f2e_audit_config_from_file(DEEP_CONFIG));
}

static void exercise_codegen_and_coercion(void) {
  static const char *const payloads[] = {
      "{}",
      "{\"PORT\":\"2147483647\",\"RATIO\":\"1e308\",\"ITEMS\":\"[]\",\"LABELS\":\"{}\"}",
      "{\"PORT\":\"-2147483648\",\"RATIO\":\"-0.0\",\"ITEMS\":[1,2],\"LABELS\":{\"tier\":2}}",
      "{\"PORT\":\"999999999999999999999999\",\"RATIO\":\"nan\",\"ITEMS\":\"{}\",\"LABELS\":\"[]\"}",
      "[]",
      "null",
      "not-json",
  };
  static const char *const languages[] = {
      "typescript", "python", "go", "rust", "java", "csharp", "dart", "json-schema",
  };

  size_t i;
  for (i = 0; i < ARRAY_LEN(payloads); ++i) {
    consume_owned("coerce boundary payload",
                  f2e_coerce_json_from_file(CODEGEN_CONFIG, payloads[i]));
  }
  for (i = 0; i < ARRAY_LEN(languages); ++i) {
    consume_owned("generate types",
                  f2e_generate_types_from_file(CODEGEN_CONFIG, languages[i], "SanitizerConfig"));
  }
}

static void exercise_long_argv_value(void) {
  const size_t length = 128U * 1024U;
  char *value = (char *)malloc(length + 1U);
  const char *argv[3];

  if (value == NULL) {
    fail("long argv", "allocation failed");
  }
  memset(value, 'x', length);
  value[length] = '\0';

  argv[0] = "tool";
  argv[1] = "--host";
  argv[2] = value;
  consume_owned("long argv string",
                f2e_parse_structured_from_file(FIXTURE_CONFIG, argv_count("long argv", ARRAY_LEN(argv)), argv));
  free(value);
}

int main(void) {
  exercise_json_argv_boundaries();
  exercise_deep_aliases();
  exercise_codegen_and_coercion();
  exercise_long_argv_value();
  f2e_free(NULL);
  return 0;
}
