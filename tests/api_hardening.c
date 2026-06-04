#include "parser.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define FIXTURE_CONFIG "tests/fixtures/.cli-flags.toml"
#define EQUALS_ONLY_CONFIG "tests/equals-only/.cli-flags.toml"
#define STOP_POSITIONALS_CONFIG "tests/stop-positionals/.cli-flags.toml"
#define INVALID_PARSE_CONFIG "tests/audit-invalid-parse/.cli-flags.toml"
#define TYPED_CONFIG "tests/typed/.cli-flags.toml"
#define INVALID_TYPED_CONFIG "tests/audit-invalid-typed/.cli-flags.toml"
#define ENV_AUDIT_CONFIG "tests/env-audit/.cli-flags.toml"
#define ENV_AUDIT_ENV "tests/env-audit/.env"
#define ENV_AUDIT_CLEAN_CONFIG "tests/env-audit-clean/.cli-flags.toml"
#define DEFAULT_JSON "{\"PORT\":\"3000\",\"DEBUG\":\"false\",\"COLOR\":\"true\"}"

static void expect_json(const char *label, char *actual, const char *expected) {
  if (!actual) {
    fprintf(stderr, "%s returned NULL\n", label);
    exit(1);
  }
  if (strcmp(actual, expected) != 0) {
    fprintf(stderr, "%s expected:\n%s\nactual:\n%s\n", label, expected, actual);
    f2e_free(actual);
    exit(1);
  }
  f2e_free(actual);
}

static void expect_status(const char *label, int actual, int expected) {
  if (actual != expected) {
    fprintf(stderr, "%s expected status %d, got %d\n", label, expected, actual);
    exit(1);
  }
}

static void expect_contains(const char *label, const char *actual, const char *needle) {
  if (!actual) {
    fprintf(stderr, "%s returned NULL\n", label);
    exit(1);
  }
  if (!strstr(actual, needle)) {
    fprintf(stderr, "%s expected to contain:\n%s\nactual:\n%s\n", label, needle, actual);
    exit(1);
  }
}

int main(void) {
  const char *stop_argv[] = {"app", "--", "--port", "9999", "--debug"};
  expect_json("double dash stop", f2e_parse_from_file(FIXTURE_CONFIG, 5, stop_argv), DEFAULT_JSON);

  const char *normal_argv[] = {"app", "--debug=1", "--debug=0", "--port", "8181"};
  expect_json("last bool alias wins", f2e_parse_from_file(FIXTURE_CONFIG, 5, normal_argv),
              "{\"PORT\":\"8181\",\"DEBUG\":\"false\",\"COLOR\":\"true\"}");

  const char *subcommand_argv[] = {"app", "exec", "--port", "8181", "--debug"};
  expect_json("default ignores positionals and keeps scanning", f2e_parse_from_file(FIXTURE_CONFIG, 5, subcommand_argv),
              "{\"PORT\":\"8181\",\"DEBUG\":\"true\",\"COLOR\":\"true\"}");

  const char *missing_string_value[] = {"app", "--port", "--debug"};
  expect_json("string flag without value is not set to true", f2e_parse_from_file(FIXTURE_CONFIG, 3, missing_string_value),
              "{\"PORT\":\"3000\",\"DEBUG\":\"true\",\"COLOR\":\"true\"}");

  const char *unknown_after_string_flag[] = {"app", "--port", "--unknown"};
  expect_json("string flag does not consume unknown option token", f2e_parse_from_file(FIXTURE_CONFIG, 3, unknown_after_string_flag),
              DEFAULT_JSON);

  const char *short_unknown_after_string_flag[] = {"app", "-p", "--unknown"};
  expect_json("short string flag does not consume unknown option token", f2e_parse_from_file(FIXTURE_CONFIG, 3, short_unknown_after_string_flag),
              DEFAULT_JSON);

  const char *dash_prefixed_string_with_equals[] = {"app", "--host=-internal"};
  expect_json("dash-prefixed string value uses equals form", f2e_parse_from_file(FIXTURE_CONFIG, 2, dash_prefixed_string_with_equals),
              "{\"PORT\":\"3000\",\"DEBUG\":\"false\",\"COLOR\":\"true\",\"HOST\":\"-internal\"}");

  const char *strict_separated[] = {"app", "--port", "8181", "--debug", "true", "--unknown", "value", "--", "--after"};
  expect_json("equals-only leaves separated values positional",
              f2e_parse_from_file(EQUALS_ONLY_CONFIG, 9, strict_separated),
              "{\"PORT\":\"3000\",\"DEBUG\":\"true\",\"F2E_POSITIONALS\":\"[\\\"app\\\",\\\"8181\\\",\\\"true\\\",\\\"value\\\",\\\"--after\\\"]\",\"F2E_UNKNOWN_OPTIONS\":\"[\\\"--unknown\\\"]\"}");

  const char *strict_inline[] = {"--port=8181", "--debug=false", "-p9000", "-d=0"};
  expect_json("equals-only still accepts inline values",
              f2e_parse_from_file(EQUALS_ONLY_CONFIG, 4, strict_inline),
              "{\"PORT\":\"9000\",\"DEBUG\":\"false\"}");

  const char *stop_positionals[] = {"exec", "--debug=true"};
  expect_json("stop at first positional",
              f2e_parse_from_file(STOP_POSITIONALS_CONFIG, 2, stop_positionals),
              "{\"DEBUG\":\"false\",\"F2E_POSITIONALS\":\"[\\\"exec\\\",\\\"--debug=true\\\"]\"}");

  const char *typed_valid[] = {"app", "--must-be-int", "1", "--is-json", "{\"foo\":\"bar\"}"};
  expect_json("typed int and json valid",
              f2e_parse_from_file(TYPED_CONFIG, 5, typed_valid),
              "{\"MUST_BE_INT\":\"1\",\"IS_JSON\":\"{\\\"foo\\\":\\\"bar\\\"}\"}");

  const char *typed_negative_values[] = {"app", "--must-be-int", "-1", "--is-json", "-2"};
  expect_json("typed negative values can be separated",
              f2e_parse_from_file(TYPED_CONFIG, 5, typed_negative_values),
              "{\"MUST_BE_INT\":\"-1\",\"IS_JSON\":\"-2\"}");

  const char *typed_unknown_after_int[] = {"app", "--must-be-int", "--bad"};
  expect_json("typed int does not consume unknown option token",
              f2e_parse_from_file(TYPED_CONFIG, 3, typed_unknown_after_int),
              "{\"MUST_BE_INT\":\"5\"}");

  const char *typed_invalid[] = {"app", "--must-be-int", "x", "--is-json", "{bad"};
  expect_json("typed int and json invalid",
              f2e_parse_from_file(TYPED_CONFIG, 5, typed_invalid),
              "{\"MUST_BE_INT\":\"5\",\"F2E_PARSE_ERRORS\":\"[\\\"flags.must_be_int value \\\\\\\"x\\\\\\\" is not a valid int\\\",\\\"flags.is_json value \\\\\\\"{bad\\\\\\\" is not valid JSON\\\"]\"}");

  expect_json("null argv with positive argc", f2e_parse_from_file(FIXTURE_CONFIG, 5, NULL), DEFAULT_JSON);
  expect_json("negative argc", f2e_parse_from_file(FIXTURE_CONFIG, -10, normal_argv), DEFAULT_JSON);
  expect_json("missing config", f2e_parse_from_file(NULL, 5, normal_argv), "{}");
  expect_json("null json argv", f2e_parse_json_argv_from_file(FIXTURE_CONFIG, NULL), "{}");
  expect_json("non-array json argv", f2e_parse_json_argv_from_file(FIXTURE_CONFIG, "{\"argv\":[]}"), "{}");
  expect_json("trailing-comma json argv", f2e_parse_json_argv_from_file(FIXTURE_CONFIG, "[\"app\",]"), "{}");

  expect_json("json argv escaping",
              f2e_parse_json_argv_from_file(FIXTURE_CONFIG, "[\"app\",\"--host\",\"quote\\\"slash\\\\line\\n\"]"),
              "{\"PORT\":\"3000\",\"DEBUG\":\"false\",\"COLOR\":\"true\",\"HOST\":\"quote\\\"slash\\\\line\\n\"}");

  expect_status("valid fixture audit", f2e_audit_config_status_from_file(FIXTURE_CONFIG), 0);
  expect_status("invalid bool default audit", f2e_audit_config_status_from_file("tests/audit-invalid-default/.cli-flags.toml"), 1);
  expect_json("invalid bool default audit report",
              f2e_audit_config_from_file("tests/audit-invalid-default/.cli-flags.toml"),
              "{\"ok\":false,\"errorCount\":1,\"warningCount\":0,\"errors\":[\"flags.debug default \\\"maybe\\\" is not a valid bool value\"],\"warnings\":[]}");

  expect_status("invalid parse env audit", f2e_audit_config_status_from_file(INVALID_PARSE_CONFIG), 1);
  expect_json("invalid parse env audit report",
              f2e_audit_config_from_file(INVALID_PARSE_CONFIG),
              "{\"ok\":false,\"errorCount\":3,\"warningCount\":0,\"errors\":[\"parse.positionals_env collides with flags.port env \\\"PORT\\\"\",\"parse.unknown_options_env collides with flags.port env \\\"PORT\\\"\",\"parse.positionals_env and parse.unknown_options_env both use env \\\"PORT\\\"\"],\"warnings\":[]}");

  expect_status("invalid typed defaults audit", f2e_audit_config_status_from_file(INVALID_TYPED_CONFIG), 1);
  expect_json("invalid typed defaults audit report",
              f2e_audit_config_from_file(INVALID_TYPED_CONFIG),
              "{\"ok\":false,\"errorCount\":2,\"warningCount\":0,\"errors\":[\"flags.must_be_int default \\\"x\\\" is not a valid int\",\"flags.is_json default \\\"{bad\\\" is not valid JSON\"],\"warnings\":[]}");

  char *bash_completion = f2e_completion_script_from_file(FIXTURE_CONFIG, "bash", "mycli");
  expect_contains("bash completion command binding", bash_completion,
                  "complete -o default -F _flags2env_complete_mycli -- 'mycli'");
  expect_contains("bash completion long aliases", bash_completion, "--listen-port=");
  expect_contains("bash completion bool aliases", bash_completion,
                  "bool_value_opts='--debug -d --verbose -v --color -c'");
  f2e_free(bash_completion);

  char *zsh_completion = f2e_completion_script_from_file(FIXTURE_CONFIG, "zsh", "mycli");
  expect_contains("zsh completion compdef", zsh_completion, "#compdef mycli");
  expect_contains("zsh completion value spec", zsh_completion, "'--port[PORT]:value:'");
  expect_contains("zsh completion negated bool", zsh_completion, "'--no-debug[DEBUG]'");
  f2e_free(zsh_completion);

  char *unsupported_completion = f2e_completion_script_from_file(FIXTURE_CONFIG, "fish", "mycli");
  if (unsupported_completion) {
    fprintf(stderr, "unsupported completion shell should return NULL\n");
    f2e_free(unsupported_completion);
    exit(1);
  }

  expect_status("clean env audit", f2e_audit_env_file_status_from_file(ENV_AUDIT_CLEAN_CONFIG, NULL), 0);
  expect_json("clean env audit report",
              f2e_audit_env_file_from_file(ENV_AUDIT_CLEAN_CONFIG, NULL),
              "{\"ok\":true,\"errorCount\":0,\"warningCount\":0,\"errors\":[],\"warnings\":[]}");

  expect_status("env mismatch audit", f2e_audit_env_file_status_from_file(ENV_AUDIT_CONFIG, ENV_AUDIT_ENV), 1);
  expect_json("env mismatch audit report",
              f2e_audit_env_file_from_file(ENV_AUDIT_CONFIG, ENV_AUDIT_ENV),
              "{\"ok\":false,\"errorCount\":1,\"warningCount\":3,\"errors\":[\".env key \\\"FLAGS2ENV_EXTRA\\\" is not declared by .cli-flags.toml\"],\"warnings\":[\".env key \\\"FLAGS2ENV_DEBUG\\\" appears more than once\",\".env line 5 is not KEY=value\",\".cli-flags.toml env \\\"FLAGS2ENV_RUNTIME\\\" is not present in .env\"]}");

  return 0;
}
