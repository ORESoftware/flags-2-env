#include "parser.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define FIXTURE_CONFIG "tests/fixtures/.cli-flags.toml"
#define EQUALS_ONLY_CONFIG "tests/equals-only/.cli-flags.toml"
#define STOP_POSITIONALS_CONFIG "tests/stop-positionals/.cli-flags.toml"
#define INVALID_PARSE_CONFIG "tests/audit-invalid-parse/.cli-flags.toml"
#define INVALID_CONFIG_LISTS_CONFIG "tests/audit-invalid-config-lists/.cli-flags.toml"
#define INVALID_CONFIG_OPTIONS_CONFIG "tests/audit-invalid-config-options/.cli-flags.toml"
#define INVALID_ENV_ONLY_CONFIG "tests/audit-invalid-env-only/.cli-flags.toml"
#define TYPED_CONFIG "tests/typed/.cli-flags.toml"
#define NATIVE_SCALARS_CONFIG "tests/native-scalars/.cli-flags.toml"
#define CODEGEN_CONFIG "tests/codegen/.cli-flags.toml"
#define INVALID_CODEGEN_CONFIG "tests/audit-invalid-codegen/.cli-flags.toml"
#define INVALID_TYPED_CONFIG "tests/audit-invalid-typed/.cli-flags.toml"
#define INVALID_TYPE_CONFIG "tests/audit-invalid-type/.cli-flags.toml"
#define ENV_AUDIT_CONFIG "tests/env-audit/.cli-flags.toml"
#define ENV_AUDIT_ENV "tests/env-audit/.env"
#define ENV_AUDIT_CLEAN_CONFIG "tests/env-audit-clean/.cli-flags.toml"
#define ENV_AUDIT_IGNORE_CONFIG "tests/env-audit-ignore/.cli-flags.toml"
#define UNSAFE_SHELL_CONFIG "tests/audit-unsafe-shell/.cli-flags.toml"
#define HELP_HARDENING_CONFIG "tests/help-hardening/.cli-flags.toml"
#define TABLE_OPTIONS_CONFIG "tests/table-options/.cli-flags.toml"
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

  const char *missing_value[] = {"app", "--port", "--debug"};
  expect_json("integer flag without value is not set to true", f2e_parse_from_file(FIXTURE_CONFIG, 3, missing_value),
              "{\"PORT\":\"3000\",\"DEBUG\":\"true\",\"COLOR\":\"true\"}");

  const char *unknown_after_value_flag[] = {"app", "--port", "--unknown"};
  expect_json("integer flag does not consume unknown option token", f2e_parse_from_file(FIXTURE_CONFIG, 3, unknown_after_value_flag),
              DEFAULT_JSON);

  const char *short_unknown_after_value_flag[] = {"app", "-p", "--unknown"};
  expect_json("short integer flag does not consume unknown option token", f2e_parse_from_file(FIXTURE_CONFIG, 3, short_unknown_after_value_flag),
              DEFAULT_JSON);

  const char *invalid_integer_port[] = {"app", "--port", "x"};
  expect_json("integer flag rejects invalid separated value", f2e_parse_from_file(FIXTURE_CONFIG, 3, invalid_integer_port),
              DEFAULT_JSON);

  const char *invalid_integer_port_inline[] = {"app", "--port=x"};
  expect_json("integer flag rejects invalid inline value", f2e_parse_from_file(FIXTURE_CONFIG, 2, invalid_integer_port_inline),
              DEFAULT_JSON);

  const char *negative_integer_port[] = {"app", "--port", "-1"};
  expect_json("integer flag accepts negative separated value", f2e_parse_from_file(FIXTURE_CONFIG, 3, negative_integer_port),
              "{\"PORT\":\"-1\",\"DEBUG\":\"false\",\"COLOR\":\"true\"}");

  const char *positive_integer_port[] = {"app", "--port", "+7"};
  expect_json("integer flag accepts explicit plus sign", f2e_parse_from_file(FIXTURE_CONFIG, 3, positive_integer_port),
              "{\"PORT\":\"+7\",\"DEBUG\":\"false\",\"COLOR\":\"true\"}");

  const char *negated_integer_port[] = {"app", "--no-port=8181"};
  expect_json("non-bool flag ignores no-prefix form", f2e_parse_from_file(FIXTURE_CONFIG, 2, negated_integer_port),
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

  const char *strict_negated_non_bool[] = {"app", "--no-port=8181"};
  expect_json("equals-only reports negated non-bool as unknown",
              f2e_parse_from_file(EQUALS_ONLY_CONFIG, 2, strict_negated_non_bool),
              "{\"PORT\":\"3000\",\"DEBUG\":\"false\",\"F2E_POSITIONALS\":\"[\\\"app\\\"]\",\"F2E_UNKNOWN_OPTIONS\":\"[\\\"--no-port=8181\\\"]\"}");

  const char *allow_unknown[] = {"app", "--allow-unknown", "--future", "value", "--debug=true"};
  expect_json("allow unknown suppresses unknown option collection",
              f2e_parse_from_file(EQUALS_ONLY_CONFIG, 5, allow_unknown),
              "{\"PORT\":\"3000\",\"DEBUG\":\"true\",\"F2E_POSITIONALS\":\"[\\\"app\\\",\\\"value\\\"]\"}");

  const char *allow_unknown_false[] = {"app", "--allow-unknown=false", "--future"};
  expect_json("allow unknown false keeps unknown option collection",
              f2e_parse_from_file(EQUALS_ONLY_CONFIG, 3, allow_unknown_false),
              "{\"PORT\":\"3000\",\"DEBUG\":\"false\",\"F2E_POSITIONALS\":\"[\\\"app\\\"]\",\"F2E_UNKNOWN_OPTIONS\":\"[\\\"--future\\\"]\"}");

  const char *stop_positionals[] = {"exec", "--debug=true"};
  expect_json("stop at first positional",
              f2e_parse_from_file(STOP_POSITIONALS_CONFIG, 2, stop_positionals),
              "{\"DEBUG\":\"false\",\"F2E_POSITIONALS\":\"[\\\"exec\\\",\\\"--debug=true\\\"]\"}");

  const char *native_defaults[] = {"app"};
  expect_json("native TOML scalar defaults become strings",
              f2e_parse_from_file(NATIVE_SCALARS_CONFIG, 1, native_defaults),
              "{\"PORT\":\"3000\",\"DEBUG\":\"false\",\"PAYLOAD\":\"7\"}");

  const char *native_overrides[] = {"app", "--debug", "1", "--payload", "true", "--port", "+12"};
  expect_json("native TOML scalar config accepts typed overrides",
              f2e_parse_from_file(NATIVE_SCALARS_CONFIG, 7, native_overrides),
              "{\"PORT\":\"+12\",\"DEBUG\":\"true\",\"PAYLOAD\":\"true\"}");

  const char *codegen_values[] = {"app", "--ratio", "-1.25", "--items", "[3,4]", "--labels", "{\"tier\":2}", "--payload", "null"};
  expect_json("double and JSON container values remain strings before coercion",
              f2e_parse_from_file(CODEGEN_CONFIG, 9, codegen_values),
              "{\"PORT\":\"3000\",\"RATIO\":\"-1.25\",\"DEBUG\":\"false\",\"ITEMS\":\"[3,4]\",\"LABELS\":\"{\\\"tier\\\":2}\",\"UNTYPED\":\"123\",\"PAYLOAD\":\"null\"}");

  const char *invalid_containers[] = {"app", "--items={\"bad\":1}", "--labels=[]"};
  expect_json("array and map types reject the wrong JSON container",
              f2e_parse_from_file(CODEGEN_CONFIG, 3, invalid_containers),
              "{\"PORT\":\"3000\",\"RATIO\":\"0.5\",\"DEBUG\":\"false\",\"ITEMS\":\"[1,\\\"two\\\"]\",\"LABELS\":\"{\\\"region\\\":\\\"us\\\"}\",\"UNTYPED\":\"123\",\"F2E_PARSE_ERRORS\":\"[\\\"flags.items value \\\\\\\"{\\\\\\\"bad\\\\\\\":1}\\\\\\\" is not a valid JSON array\\\",\\\"flags.labels value \\\\\\\"[]\\\\\\\" is not a valid JSON object\\\"]\"}");

  expect_json("coerce strings and schema defaults",
              f2e_coerce_json_from_file(CODEGEN_CONFIG,
                                        "{\"RATIO\":\"1.25\",\"ITEMS\":\"[3,4]\",\"LABELS\":\"{\\\"tier\\\":2}\",\"PAYLOAD\":\"null\",\"IGNORED\":\"x\"}"),
              "{\"ok\":true,\"value\":{\"PORT\":3000,\"RATIO\":1.25,\"DEBUG\":false,\"ITEMS\":[3,4],\"LABELS\":{\"tier\":2},\"PAYLOAD\":null,\"UNTYPED\":\"123\"}}");

  expect_json("coerce accepts already typed JSON values",
              f2e_coerce_json_from_file(CODEGEN_CONFIG,
                                        "{\"PORT\":42,\"DEBUG\":true,\"ITEMS\":[1],\"LABELS\":{\"a\":1}}"),
              "{\"ok\":true,\"value\":{\"PORT\":42,\"RATIO\":0.5,\"DEBUG\":true,\"ITEMS\":[1],\"LABELS\":{\"a\":1},\"UNTYPED\":\"123\"}}");

  expect_json("coerce aggregates type errors",
              f2e_coerce_json_from_file(CODEGEN_CONFIG,
                                        "{\"PORT\":\"nope\",\"RATIO\":\"nan\",\"ITEMS\":\"{}\",\"LABELS\":\"[]\"}"),
              "{\"ok\":false,\"errors\":[\"env PORT (flags.port) must be an integer because .cli-flags.toml declares type = \\\"integer\\\"; received a string. Set PORT to an integer or update flags.port.type\",\"env RATIO (flags.ratio) must be a finite number because .cli-flags.toml declares type = \\\"double\\\"; received a string. Set RATIO to a finite number or update flags.ratio.type\",\"env ITEMS (flags.items) must be a JSON array because .cli-flags.toml declares type = \\\"array\\\"; received a string. Set ITEMS to a JSON array or update flags.items.type\",\"env LABELS (flags.labels) must be a JSON object because .cli-flags.toml declares type = \\\"map\\\"; received a string. Set LABELS to a JSON object or update flags.labels.type\"]}");

  expect_json("coerce preserves parser errors",
              f2e_coerce_json_from_file(CODEGEN_CONFIG,
                                        "{\"F2E_PARSE_ERRORS\":\"[\\\"flags.ratio value is invalid\\\"]\"}"),
              "{\"ok\":false,\"errors\":[\"flags.ratio value is invalid\"]}");

  expect_json("coerce rejects non-object input",
              f2e_coerce_json_from_file(CODEGEN_CONFIG, "[]"),
              "{\"ok\":false,\"errors\":[\"values must be a valid JSON object with supported value sizes\"]}");

  char *typescript_types = f2e_generate_types_from_file(CODEGEN_CONFIG, "typescript", "CliStuff");
  expect_contains("typescript codegen interface", typescript_types, "export interface CliStuff");
  expect_contains("typescript codegen number", typescript_types, "RATIO: number;");
  expect_contains("typescript codegen optional string", typescript_types, "NAME?: string;");
  expect_contains("typescript codegen map", typescript_types, "LABELS: Record<string, unknown>;");
  expect_contains("typescript omitted type defaults to string", typescript_types, "UNTYPED: string;");
  f2e_free(typescript_types);

  const char *languages[][2] = {
      {"python", "class CliStuff("},
      {"go", "type CliStuff struct"},
      {"rust", "pub struct CliStuff"},
      {"java", "public record CliStuff"},
      {"csharp", "public sealed record CliStuff"},
      {"dart", "final class CliStuff"},
      {"json-schema", "\"title\": \"CliStuff\""},
  };
  for (size_t i = 0; i < sizeof(languages) / sizeof(languages[0]); i++) {
    char *generated = f2e_generate_types_from_file(CODEGEN_CONFIG, languages[i][0], "CliStuff");
    expect_contains("language codegen", generated, languages[i][1]);
    f2e_free(generated);
  }

  char *json_schema = f2e_generate_types_from_file(CODEGEN_CONFIG, "json-schema", "CliStuff");
  expect_contains("json schema is post-coercion contract", json_schema,
                  "\"x-flags2env-stage\": \"coerced\"");
  expect_contains("json schema preserves declared type metadata", json_schema,
                  "\"x-flags2env-type\":\"integer\"");
  expect_contains("json schema preserves omitted type string fallback", json_schema,
                  "\"UNTYPED\": {\"type\":\"string\",\"default\":\"123\",\"x-flags2env-type\":\"string\"");
  f2e_free(json_schema);

  char *unsupported_codegen = f2e_generate_types_from_file(CODEGEN_CONFIG, "brainfuck", "CliStuff");
  if (unsupported_codegen) {
    fprintf(stderr, "unsupported codegen language should return NULL\n");
    f2e_free(unsupported_codegen);
    exit(1);
  }

  char *invalid_name_codegen = f2e_generate_types_from_file(CODEGEN_CONFIG, "typescript", "bad-name");
  if (invalid_name_codegen) {
    fprintf(stderr, "invalid generated type name should return NULL\n");
    f2e_free(invalid_name_codegen);
    exit(1);
  }

  const char *typed_valid[] = {"app", "--must-be-int", "1", "--is-json", "{\"foo\":\"bar\"}"};
  expect_json("typed integer and json valid",
              f2e_parse_from_file(TYPED_CONFIG, 5, typed_valid),
              "{\"MUST_BE_INT\":\"1\",\"IS_JSON\":\"{\\\"foo\\\":\\\"bar\\\"}\"}");

  const char *typed_plus_values[] = {"app", "--must-be-int=+7", "-i+8"};
  expect_json("typed integer accepts explicit plus sign",
              f2e_parse_from_file(TYPED_CONFIG, 3, typed_plus_values),
              "{\"MUST_BE_INT\":\"+8\"}");

  const char *typed_negative_values[] = {"app", "--must-be-int", "-1", "--is-json", "-2"};
  expect_json("typed negative values can be separated",
              f2e_parse_from_file(TYPED_CONFIG, 5, typed_negative_values),
              "{\"MUST_BE_INT\":\"-1\",\"IS_JSON\":\"-2\"}");

  const char *typed_unknown_after_int[] = {"app", "--must-be-int", "--bad"};
  expect_json("typed integer does not consume unknown option token",
              f2e_parse_from_file(TYPED_CONFIG, 3, typed_unknown_after_int),
              "{\"MUST_BE_INT\":\"5\"}");

  const char *typed_invalid[] = {"app", "--must-be-int", "x", "--is-json", "{bad"};
  expect_json("typed integer and json invalid",
              f2e_parse_from_file(TYPED_CONFIG, 5, typed_invalid),
              "{\"MUST_BE_INT\":\"5\",\"F2E_PARSE_ERRORS\":\"[\\\"flags.must_be_int value \\\\\\\"x\\\\\\\" is not a valid integer\\\",\\\"flags.is_json value \\\\\\\"{bad\\\\\\\" is not valid JSON\\\"]\"}");

  const char *typed_decimal[] = {"app", "--must-be-int=1.5"};
  expect_json("typed integer rejects decimal value",
              f2e_parse_from_file(TYPED_CONFIG, 2, typed_decimal),
              "{\"MUST_BE_INT\":\"5\",\"F2E_PARSE_ERRORS\":\"[\\\"flags.must_be_int value \\\\\\\"1.5\\\\\\\" is not a valid integer\\\"]\"}");

  const char *typed_overflow[] = {"app", "--must-be-int", "9223372036854775808"};
  expect_json("typed integer rejects overflow value",
              f2e_parse_from_file(TYPED_CONFIG, 3, typed_overflow),
              "{\"MUST_BE_INT\":\"5\",\"F2E_PARSE_ERRORS\":\"[\\\"flags.must_be_int value \\\\\\\"9223372036854775808\\\\\\\" is not a valid integer\\\"]\"}");

  const char *typed_negated_non_bool[] = {"app", "--no-must-be-int=2"};
  expect_json("typed integer ignores no-prefix form",
              f2e_parse_from_file(TYPED_CONFIG, 2, typed_negated_non_bool),
              "{\"MUST_BE_INT\":\"5\"}");

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

  expect_status("invalid config option audit", f2e_audit_config_status_from_file(INVALID_CONFIG_OPTIONS_CONFIG), 1);
  expect_json("invalid config option audit report",
              f2e_audit_config_from_file(INVALID_CONFIG_OPTIONS_CONFIG),
              "{\"ok\":false,\"errorCount\":4,\"warningCount\":0,\"errors\":[\"help.columns must be a list of supported table column names\",\"help.exclude must be a list of supported table column names\",\"env.ignore contains invalid env var name \\\"BAD-KEY\\\"\",\"env.ignore contains invalid env var name \\\"\\\"\"],\"warnings\":[]}");

  expect_status("invalid config list audit", f2e_audit_config_status_from_file(INVALID_CONFIG_LISTS_CONFIG), 1);
  expect_json("invalid config list audit report",
              f2e_audit_config_from_file(INVALID_CONFIG_LISTS_CONFIG),
              "{\"ok\":false,\"errorCount\":2,\"warningCount\":0,\"errors\":[\"help.columns must be a list of supported table column names\",\"env.ignore must be a list of env var names\"],\"warnings\":[]}");

  expect_status("invalid env-only audit", f2e_audit_config_status_from_file(INVALID_ENV_ONLY_CONFIG), 1);
  expect_json("invalid env-only audit report",
              f2e_audit_config_from_file(INVALID_ENV_ONLY_CONFIG),
              "{\"ok\":false,\"errorCount\":1,\"warningCount\":0,\"errors\":[\"flags.bad env \\\"BAD-NAME\\\" is not a valid env var name\"],\"warnings\":[]}");

  expect_status("invalid typed defaults audit", f2e_audit_config_status_from_file(INVALID_TYPED_CONFIG), 1);
  expect_json("invalid typed defaults audit report",
              f2e_audit_config_from_file(INVALID_TYPED_CONFIG),
              "{\"ok\":false,\"errorCount\":3,\"warningCount\":0,\"errors\":[\"flags.must_be_int default \\\"x\\\" is not a valid integer\",\"flags.is_json default \\\"{bad\\\" is not valid JSON\",\"flags.too_large default \\\"9223372036854775808\\\" is not a valid integer\"],\"warnings\":[]}");

  expect_status("invalid codegen defaults audit", f2e_audit_config_status_from_file(INVALID_CODEGEN_CONFIG), 1);
  expect_json("invalid codegen defaults audit report",
              f2e_audit_config_from_file(INVALID_CODEGEN_CONFIG),
              "{\"ok\":false,\"errorCount\":3,\"warningCount\":0,\"errors\":[\"flags.bad_float default \\\"nan\\\" is not a valid double\",\"flags.bad_array default \\\"{}\\\" is not a valid JSON array\",\"flags.bad_map default \\\"[]\\\" is not a valid JSON object\"],\"warnings\":[]}");

  expect_status("invalid type audit", f2e_audit_config_status_from_file(INVALID_TYPE_CONFIG), 1);
  expect_json("invalid type audit report",
              f2e_audit_config_from_file(INVALID_TYPE_CONFIG),
              "{\"ok\":false,\"errorCount\":1,\"warningCount\":0,\"errors\":[\"flags.port type \\\"integerer\\\" is not supported\"],\"warnings\":[]}");

  const char *help_argv[] = {"app", "--help"};
  expect_status("exact help token is detected", f2e_is_help_requested(2, help_argv), 1);
  expect_status("json argv help token is detected", f2e_is_help_requested_json_argv("[\"app\",\"--help\"]"), 1);
  const char *help_after_double_dash[] = {"app", "--", "--help"};
  expect_status("help after double dash is positional", f2e_is_help_requested(3, help_after_double_dash), 0);
  expect_status("json argv help after double dash is positional", f2e_is_help_requested_json_argv("[\"app\",\"--\",\"--help\"]"), 0);
  const char *short_help_argv[] = {"app", "-h"};
  expect_status("short h remains a normal flag", f2e_is_help_requested(2, short_help_argv), 0);
  expect_status("invalid json argv is not help", f2e_is_help_requested_json_argv("[\"app\",]"), 0);
  expect_status("null json argv is not help", f2e_is_help_requested_json_argv(NULL), 0);

  char *wide_help = f2e_help_table_from_file(FIXTURE_CONFIG, "app", 132);
  expect_contains("wide help has env column", wide_help, "| Env");
  expect_contains("wide help has description column", wide_help, "| Description");
  expect_contains("wide help has fixture description", wide_help, "TCP port for the app listener.");
  expect_contains("wide help has url footer", wide_help, "More help: https://example.com/flags2env/help");
  f2e_free(wide_help);

  char *narrow_help = f2e_help_table_from_file(FIXTURE_CONFIG, "app", 70);
  expect_contains("narrow help has details column", narrow_help, "| Details");
  expect_contains("narrow help includes env details", narrow_help, "env=PORT; type=integer; default=3000");
  expect_contains("narrow help has url footer", narrow_help, "More help: https://example.com/flags2env/help");
  if (strstr(narrow_help, "| Env") || strstr(narrow_help, "| Description")) {
    fprintf(stderr, "narrow help should not render wide-only columns:\n%s\n", narrow_help);
    f2e_free(narrow_help);
    exit(1);
  }
  f2e_free(narrow_help);

  char *tiny_help = f2e_help_table_from_file(FIXTURE_CONFIG, "app", 1);
  expect_contains("tiny terminal help clamps to narrow table", tiny_help, "| Details");
  f2e_free(tiny_help);

  char *huge_help = f2e_help_table_from_file(FIXTURE_CONFIG, "app", 5000);
  expect_contains("huge terminal help clamps to wide table", huge_help, "| Description");
  f2e_free(huge_help);

  char *custom_help = f2e_help_table_from_file(TABLE_OPTIONS_CONFIG, "app", 132);
  expect_contains("custom help keeps options column", custom_help, "| Option(s)");
  expect_contains("custom help keeps description column", custom_help, "| Description");
  expect_contains("custom help keeps flag help text", custom_help, "TCP port for the app listener.");
  if (strstr(custom_help, "| Env") || strstr(custom_help, "| Type") || strstr(custom_help, "| Default")) {
    fprintf(stderr, "custom help should omit excluded/unselected columns:\n%s\n", custom_help);
    f2e_free(custom_help);
    exit(1);
  }
  f2e_free(custom_help);

  char *missing_help = f2e_help_table_from_file(NULL, "app", 80);
  if (missing_help) {
    fprintf(stderr, "missing help config should return NULL\n");
    f2e_free(missing_help);
    exit(1);
  }
  expect_status("missing print table config returns failure", f2e_print_table_from_file(NULL, "app", 80), 1);

  char *sanitized_help = f2e_help_table_from_file(HELP_HARDENING_CONFIG, "app", 80);
  expect_contains("sanitized help preserves visible text", sanitized_help, "Alpha beta");
  expect_contains("sanitized help url preserves visible text", sanitized_help, "https://example.com/help with-tab");
  if (strchr(sanitized_help, '\t')) {
    fprintf(stderr, "help table should not contain raw tab controls:\n%s\n", sanitized_help);
    f2e_free(sanitized_help);
    exit(1);
  }
  f2e_free(sanitized_help);

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

  char *unsafe_command_completion = f2e_completion_script_from_file(FIXTURE_CONFIG, "bash", "bad;name");
  if (unsafe_command_completion) {
    fprintf(stderr, "unsafe completion command should return NULL\n");
    f2e_free(unsafe_command_completion);
    exit(1);
  }

  char *slash_command_completion = f2e_completion_script_from_file(FIXTURE_CONFIG, "bash", "/");
  if (slash_command_completion) {
    fprintf(stderr, "slash-only completion command should return NULL\n");
    f2e_free(slash_command_completion);
    exit(1);
  }

  char *path_command_completion = f2e_completion_script_from_file(FIXTURE_CONFIG, "zsh", "/usr/local/bin/mycli/");
  expect_contains("path command completion uses basename", path_command_completion, "#compdef mycli");
  f2e_free(path_command_completion);

  char *invalid_env_config_completion = f2e_completion_script_from_file(INVALID_ENV_ONLY_CONFIG, "bash", "mycli");
  if (invalid_env_config_completion) {
    fprintf(stderr, "invalid env-only config completion should return NULL\n");
    f2e_free(invalid_env_config_completion);
    exit(1);
  }

  char *unsafe_config_completion = f2e_completion_script_from_file(UNSAFE_SHELL_CONFIG, "bash", "mycli");
  if (unsafe_config_completion) {
    fprintf(stderr, "unsafe config completion should return NULL\n");
    f2e_free(unsafe_config_completion);
    exit(1);
  }

  expect_status("unsafe shell config audit", f2e_audit_config_status_from_file(UNSAFE_SHELL_CONFIG), 1);
  expect_json("unsafe shell config audit report",
              f2e_audit_config_from_file(UNSAFE_SHELL_CONFIG),
              "{\"ok\":false,\"errorCount\":5,\"warningCount\":0,\"errors\":[\"flags.bad env \\\"BAD-NAME\\\" is not a valid env var name\",\"flags.bad alias \\\"bad alias\\\" contains unsafe option characters\",\"flags.bad has invalid short flag \\\";\\\"\",\"flags.bad true_aliases contains unsafe shell token \\\"bad value\\\"\",\"parse.positionals_env \\\"BAD-POSITIONALS\\\" is not a valid env var name\"],\"warnings\":[]}");

  expect_status("clean env audit", f2e_audit_env_file_status_from_file(ENV_AUDIT_CLEAN_CONFIG, NULL), 0);
  expect_json("clean env audit report",
              f2e_audit_env_file_from_file(ENV_AUDIT_CLEAN_CONFIG, NULL),
              "{\"ok\":true,\"errorCount\":0,\"warningCount\":0,\"errors\":[],\"warnings\":[]}");

  expect_status("ignored env audit", f2e_audit_env_file_status_from_file(ENV_AUDIT_IGNORE_CONFIG, NULL), 0);
  expect_json("ignored env audit report",
              f2e_audit_env_file_from_file(ENV_AUDIT_IGNORE_CONFIG, NULL),
              "{\"ok\":true,\"errorCount\":0,\"warningCount\":0,\"errors\":[],\"warnings\":[]}");

  expect_status("invalid config env audit", f2e_audit_env_file_status_from_file(INVALID_ENV_ONLY_CONFIG, ENV_AUDIT_ENV), 1);
  expect_json("invalid config env audit report",
              f2e_audit_env_file_from_file(INVALID_ENV_ONLY_CONFIG, ENV_AUDIT_ENV),
              "{\"ok\":false,\"errorCount\":1,\"warningCount\":0,\"errors\":[\"flags.bad env \\\"BAD-NAME\\\" is not a valid env var name\"],\"warnings\":[]}");

  expect_status("env mismatch audit", f2e_audit_env_file_status_from_file(ENV_AUDIT_CONFIG, ENV_AUDIT_ENV), 1);
  expect_json("env mismatch audit report",
              f2e_audit_env_file_from_file(ENV_AUDIT_CONFIG, ENV_AUDIT_ENV),
              "{\"ok\":false,\"errorCount\":1,\"warningCount\":3,\"errors\":[\".env key \\\"FLAGS2ENV_EXTRA\\\" is not declared by .cli-flags.toml\"],\"warnings\":[\".env key \\\"FLAGS2ENV_DEBUG\\\" appears more than once\",\".env line 5 is not KEY=value\",\".cli-flags.toml env \\\"FLAGS2ENV_RUNTIME\\\" is not present in .env\"]}");

  return 0;
}
