#include "fixture_api.h"

/* Nullability inference must be precise, not merely conservative: a helper
 * that guards before dereferencing imposes no requirement on its callers,
 * so passing an unchecked allocation to one of these is legal. */

static size_t guarded_len(const char *p) {
  if (!p) {
    return 0;
  }
  return strlen(p);
}

static size_t guarded_len_equality(const char *p) {
  if (p == 0) {
    return 0;
  }
  return strlen(p);
}

static size_t guarded_len_positive(const char *p) {
  if (p) {
    return strlen(p);
  }
  return 0;
}

int main(void) {
  char *p = (char *)malloc(4);
  size_t total = guarded_len(p) + guarded_len_equality(p) +
                 guarded_len_positive(p);
  free(p);
  return (int)total;
}
