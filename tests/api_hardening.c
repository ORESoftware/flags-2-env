#include "parser.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define FIXTURE_CONFIG "tests/fixtures/.cli-flags.toml"
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

int main(void) {
  const char *stop_argv[] = {"app", "--", "--port", "9999", "--debug"};
  expect_json("double dash stop", f2e_parse_from_file(FIXTURE_CONFIG, 5, stop_argv), DEFAULT_JSON);

  const char *normal_argv[] = {"app", "--debug=1", "--debug=0", "--port", "8181"};
  expect_json("last bool alias wins", f2e_parse_from_file(FIXTURE_CONFIG, 5, normal_argv),
              "{\"PORT\":\"8181\",\"DEBUG\":\"false\",\"COLOR\":\"true\"}");

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

  return 0;
}
