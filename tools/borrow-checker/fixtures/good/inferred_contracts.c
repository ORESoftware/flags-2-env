#include "fixture_api.h"

/* A static helper that allocates: callers own the result. The checker must
 * infer this without any annotation, the way it infers contracts for the
 * static helpers inside parser.c. */
static char *make_label(const char *name) {
  size_t len = strlen(name);
  char *copy = (char *)malloc(len + 1);
  if (!copy) {
    return 0;
  }
  memcpy(copy, name, len + 1);
  return copy;
}

/* A static helper that releases: passing a pointer here transfers it. */
static void drop_label(char *label) {
  free(label);
}

int main(void) {
  char *label = make_label("demo");
  if (!label) {
    return 1;
  }
  drop_label(label);
  return 0;
}
