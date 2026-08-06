#if !defined(_WIN32) && !defined(_POSIX_C_SOURCE)
#define _POSIX_C_SOURCE 200809L
#endif

#include "terminal_context.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
static int set_test_env(const char *name, const char *value) {
  return _putenv_s(name, value);
}
#else
static int set_test_env(const char *name, const char *value) {
  return setenv(name, value, 1);
}
#endif

static int require_contains(const char *json, const char *needle) {
  if (!json || !strstr(json, needle)) {
    fprintf(stderr, "missing %s in %s\n", needle, json ? json : "<null>");
    return 0;
  }
  return 1;
}

int main(void) {
  if (set_test_env("F2E_SHELL", "/usr/bin/fish") != 0 ||
      set_test_env("F2E_FORCE_STDIN_TTY", "1") != 0 ||
      set_test_env("F2E_FORCE_STDOUT_TTY", "0") != 0 ||
      set_test_env("F2E_FORCE_STDERR_TTY", "1") != 0 ||
      set_test_env("F2E_FORCE_CI", "0") != 0 ||
      set_test_env("F2E_FORCE_COLOR", "1") != 0 ||
      set_test_env("F2E_FORCE_UNICODE", "1") != 0 ||
      set_test_env("COLUMNS", "132") != 0) {
    return 1;
  }

  char *json = f2e_terminal_context_json();
  int ok = require_contains(json, "\"version\":1") &&
           require_contains(json, "\"stdinTty\":true") &&
           require_contains(json, "\"stdoutTty\":false") &&
           require_contains(json, "\"stderrTty\":true") &&
           require_contains(json, "\"canPrompt\":true") &&
           require_contains(json, "\"outputMode\":\"plain\"") &&
           require_contains(json, "\"shell\":\"fish\"") &&
           require_contains(json, "\"shellSource\":\"override\"") &&
           require_contains(json, "\"colorStderr\":true") &&
           require_contains(json, "\"unicode\":true") &&
           require_contains(json, "\"columns\":132");
  free(json);

  char *env = f2e_terminal_context_env_json();
  ok = ok && require_contains(env, "\"F2E_CONTEXT_SHELL\":\"fish\"") &&
       require_contains(env, "\"F2E_CONTEXT_COLUMNS\":\"132\"");
  free(env);
  return ok ? 0 : 1;
}
