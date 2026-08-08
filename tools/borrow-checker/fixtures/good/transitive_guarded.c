#include "fixture_api.h"

/* The mirror of transitive_null_deref: a guard anywhere on the chain
 * discharges the obligation for everyone above it, so forwarding an
 * unchecked allocation into this chain is legal and must stay silent. */

static size_t innermost(const char *p) { return strlen(p); }

static size_t middle(const char *p) {
  if (!p) {
    return 0;
  }
  return innermost(p);
}

static size_t outer(const char *p) { return middle(p); }

int main(void) {
  char *p = (char *)malloc(4);
  size_t n = outer(p);
  free(p);
  return (int)n;
}
