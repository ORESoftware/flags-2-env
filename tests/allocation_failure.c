#if defined(__linux__) && !defined(_POSIX_C_SOURCE)
#define _POSIX_C_SOURCE 200809L
#endif

#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>

static size_t f2e_test_allocation_calls;
static size_t f2e_test_fail_at;

static int f2e_test_should_fail(void) {
  f2e_test_allocation_calls++;
  return f2e_test_fail_at == f2e_test_allocation_calls;
}

static void *f2e_test_malloc(size_t size) {
  if (f2e_test_should_fail()) {
    return NULL;
  }
  return malloc(size);
}

static void *f2e_test_calloc(size_t count, size_t size) {
  if (f2e_test_should_fail()) {
    return NULL;
  }
  return calloc(count, size);
}

static void *f2e_test_realloc(void *value, size_t size) {
  if (f2e_test_should_fail()) {
    return NULL;
  }
  return realloc(value, size);
}

#define malloc f2e_test_malloc
#define calloc f2e_test_calloc
#define realloc f2e_test_realloc
#include "../src/parser.c"
#undef realloc
#undef calloc
#undef malloc

static const char *fixture_path;

static char *completion_bash(void) {
  return f2e_completion_script_from_file(fixture_path, "bash", "fuzz");
}

static char *completion_zsh(void) {
  return f2e_completion_script_from_file(fixture_path, "zsh", "fuzz");
}

static char *generate_typescript(void) {
  return f2e_generate_types_from_file(fixture_path, "typescript", "FuzzConfig");
}

static char *generate_schema(void) {
  return f2e_generate_types_from_file(fixture_path, "json-schema", "FuzzConfig");
}

static char *parse_argv(void) {
  return f2e_parse_json_argv_from_file(
      fixture_path,
      "[\"fuzz\",\"ws\",\"remote\",\"add\",\"tag\",\"--name\",\"stable\"]");
}

static char *parse_structured_argv(void) {
  return f2e_parse_structured_json_argv_from_file(
      fixture_path,
      "[\"fuzz\",\"ws\",\"remote\",\"add\",\"tag\",\"--name\",\"stable\"]");
}

static char *render_help(void) {
  return f2e_help_table_for_json_argv_from_file(
      fixture_path,
      "fuzz",
      "[\"fuzz\",\"ws\",\"remote\",\"add\",\"tag\",\"--help\"]",
      100);
}

static char *coerce_values(void) {
  return f2e_coerce_json_from_file(
      fixture_path,
      "{\"TOOL_DRY_RUN\":\"true\",\"TOOL_TAG_NAME\":\"stable\"}");
}

typedef char *(*F2ETestOperation)(void);

static int exercise_failures(const char *name, F2ETestOperation operation) {
  f2e_test_fail_at = 0;
  f2e_test_allocation_calls = 0;
  char *result = operation();
  size_t normal_calls = f2e_test_allocation_calls;
  if (!result || normal_calls == 0) {
    fprintf(stderr, "%s baseline failed\n", name);
    f2e_free(result);
    return 0;
  }
  f2e_free(result);

  /*
   * Fail each allocation once. The extra attempts cover recovery paths that
   * may allocate after the normal successful path's final allocation.
   */
  for (size_t fail_at = 1; fail_at <= normal_calls + 64; fail_at++) {
    f2e_test_fail_at = fail_at;
    f2e_test_allocation_calls = 0;
    result = operation();
    f2e_free(result);
  }

  printf("allocation-failure: %s (%lu allocation points)\n",
         name,
         (unsigned long)normal_calls);
  return 1;
}

int main(int argc, char **argv) {
  if (argc != 2) {
    fprintf(stderr, "usage: %s path/to/.cli-flags.toml\n", argv[0]);
    return 2;
  }
  fixture_path = argv[1];

  const struct {
    const char *name;
    F2ETestOperation operation;
  } operations[] = {
      {"bash completion", completion_bash},
      {"zsh completion", completion_zsh},
      {"TypeScript generation", generate_typescript},
      {"JSON Schema generation", generate_schema},
      {"argv parse", parse_argv},
      {"structured argv parse", parse_structured_argv},
      {"help rendering", render_help},
      {"value coercion", coerce_values},
  };

  int ok = 1;
  for (size_t i = 0; i < sizeof(operations) / sizeof(operations[0]); i++) {
    ok = exercise_failures(operations[i].name, operations[i].operation) && ok;
  }
  return ok ? 0 : 1;
}
