#include "fixture_api.h"

/* C short-circuit evaluation is a guard. The right operand of && runs only
 * when the left was true, and the right operand of || only when the left
 * was false, so these dereferences are all protected and none of them may
 * be diagnosed. This is the shape real CLI code uses to chain fallible
 * steps in one condition. */

static size_t strict_len(const char *p) { return strlen(p); }

int and_chain(void) {
  char *p = (char *)malloc(4);
  size_t n = 0;
  if (p && strict_len(p) > 0) {
    n = strict_len(p);
  }
  free(p);
  return (int)n;
}

int or_chain(void) {
  char *a = (char *)malloc(4);
  char *b = (char *)malloc(4);
  if (!a || !b || strict_len(a) == 0 || strict_len(b) == 0) {
    free(a);
    free(b);
    return 1;
  }
  free(a);
  free(b);
  return 0;
}

int mixed_chain(void) {
  char *p = (char *)malloc(4);
  if (p != 0 && *p == 'x') {
    free(p);
    return 1;
  }
  free(p);
  return 0;
}
