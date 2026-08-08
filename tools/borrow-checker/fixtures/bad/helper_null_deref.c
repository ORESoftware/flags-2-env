#include "fixture_api.h"

/* An unchecked allocation handed to a local helper that dereferences the
 * parameter without guarding it. The dereference is one call away, but the
 * segfault is the caller's. */

// EXPECT: null-deref
static void read_first(const char *p) { (void)*p; }

int main(void) {
  char *p = (char *)malloc(4);
  read_first(p);
  free(p);
  return 0;
}
