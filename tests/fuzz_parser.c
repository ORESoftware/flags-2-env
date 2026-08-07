#include "parser.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define F2E_FUZZ_MAX_INPUT 8192

static void consume_owned(char *value) {
  f2e_free(value);
}

static int write_bytes(const char *path, const uint8_t *data, size_t size) {
  FILE *file = fopen(path, "wb");
  if (!file) {
    return 0;
  }
  size_t written = fwrite(data, 1, size, file);
  int closed = fclose(file);
  return written == size && closed == 0;
}

/*
 * Builds a ./.env whose declared keys carry the fuzz bytes as values and whose
 * tail is the raw bytes, so one input exercises key validation, quote and
 * escape handling, inline comments, oversized lines, and per-type value
 * normalization at once.
 */
static int write_dotenv(const char *path, const uint8_t *data, size_t size) {
  static const char *const keys[] = {
      "F2E_FUZZ_STR", "F2E_FUZZ_INT", "F2E_FUZZ_BOOL", "F2E_FUZZ_JSON"};
  FILE *file = fopen(path, "wb");
  if (!file) {
    return 0;
  }
  int ok = 1;
  for (size_t i = 0; i < sizeof(keys) / sizeof(keys[0]); i++) {
    if (fprintf(file, "%s=", keys[i]) < 0 || fwrite(data, 1, size, file) != size ||
        fputc('\n', file) == EOF) {
      ok = 0;
      break;
    }
  }
  if (ok && (fwrite(data, 1, size, file) != size || fputc('\n', file) == EOF)) {
    ok = 0;
  }
  return fclose(file) == 0 && ok;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  if (!data || size == 0 || size > F2E_FUZZ_MAX_INPUT) {
    return 0;
  }

  const char *fixture = getenv("F2E_FUZZ_FIXTURE");
  const char *config_path = getenv("F2E_FUZZ_CONFIG");
  const char *env_path = getenv("F2E_FUZZ_ENV");
  if (!fixture || !config_path || !env_path) {
    return 0;
  }

  /* .env is only ever read from the working directory, so move there once and
     stay: every other path this harness uses is absolute */
  static int cwd_ready = 0;
  const char *dotenv_config = getenv("F2E_FUZZ_DOTENV_CONFIG");
  const char *dotenv_cwd = getenv("F2E_FUZZ_DOTENV_CWD");
  if (!cwd_ready && dotenv_cwd) {
    cwd_ready = chdir(dotenv_cwd) == 0 ? 1 : -1;
  }

  char *text = (char *)malloc(size + 1);
  if (!text) {
    return 0;
  }
  memcpy(text, data, size);
  text[size] = '\0';

  switch (data[0] % 5) {
    case 0:
      consume_owned(f2e_parse_json_argv_from_file(fixture, text));
      consume_owned(f2e_parse_structured_json_argv_from_file(fixture, text));
      consume_owned(f2e_resolve_commands_json_argv_from_file(fixture, text));
      consume_owned(f2e_help_table_for_json_argv_from_file(fixture, "fuzz", text, 80));
      (void)f2e_is_help_requested_json_argv(text);
      break;

    case 1:
      if (write_bytes(config_path, data + 1, size - 1)) {
        consume_owned(f2e_audit_config_from_file(config_path));
        consume_owned(f2e_parse_json_argv_from_file(config_path, "[\"fuzz\",\"run\",\"--flag=value\"]"));
        consume_owned(f2e_parse_structured_json_argv_from_file(
            config_path, "[\"fuzz\",\"run\",\"--flag=value\",\"--\",\"operand\"]"));
        consume_owned(f2e_help_table_for_json_argv_from_file(
            config_path, "fuzz", "[\"fuzz\",\"run\",\"--help\"]", 80));
        consume_owned(f2e_completion_script_from_file(config_path, "bash", "fuzz"));
        consume_owned(f2e_completion_script_from_file(config_path, "zsh", "fuzz"));
        consume_owned(f2e_generate_types_from_file(config_path, "typescript", "FuzzConfig"));
        consume_owned(f2e_generate_types_from_file(config_path, "json-schema", "FuzzConfig"));
      }
      break;

    case 2:
      consume_owned(f2e_coerce_json_from_file(fixture, text));
      break;

    case 3:
      if (write_bytes(env_path, data + 1, size - 1)) {
        consume_owned(f2e_audit_env_file_from_file(fixture, env_path));
        (void)f2e_audit_env_file_status_from_file(fixture, env_path);
      }
      break;
  }

  free(text);
  return 0;
}
