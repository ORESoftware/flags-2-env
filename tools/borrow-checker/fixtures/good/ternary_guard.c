#include "fixture_api.h"

/* A ternary is a guard exactly as an if-statement is. This is the shape
 * parser.c uses to pass an optionally-allocated table into a helper that
 * dereferences it, so getting it wrong reports a defect in correct code. */

static size_t strict_len(const char *p) { return strlen(p); }

size_t optional_len(const char *maybe) {
  return maybe ? strict_len(maybe) : 0;
}

size_t optional_len_negated(const char *maybe) {
  return !maybe ? 0 : strict_len(maybe);
}

int main(void) {
  char *p = (char *)malloc(4);
  size_t n = optional_len(p) + optional_len_negated(p);
  free(p);
  return (int)n;
}
