#include "fixture_api.h"

/* The canonical contract: allocate, null-check, use, release exactly once. */
size_t roundtrip(void) {
  const char *argv[] = {"app", "--help"};
  char *json = fx_parse(2, argv);
  if (!json) {
    return 0;
  }
  size_t len = strlen(json);
  fx_free(json);
  return len;
}

/* Transfer via return: the caller inherits the obligation. */
char *transfer(void) {
  char *json = fx_render("demo");
  if (json == 0) {
    return 0;
  }
  return json;
}

/* Reset-to-null after free is not a use. */
int reset(void) {
  char *json = fx_render("demo");
  if (!json) {
    return 1;
  }
  fx_free(json);
  json = 0;
  return json == 0;
}

/* Conditional release on the error path, transfer on success. */
char *guarded(int wanted) {
  char *json = fx_render("demo");
  if (!json) {
    return 0;
  }
  if (!wanted) {
    fx_free(json);
    return 0;
  }
  return json;
}

/* Borrowed views are read, never released. */
size_t view(const char *label) {
  const char *alias = fx_peek(label);
  if (!alias) {
    return 0;
  }
  return strlen(alias);
}
