#include "fixture_api.h"

/* The non-null obligation has to survive a call chain. `outer` never
 * dereferences anything itself; it forwards its parameter to a helper that
 * does. If the requirement dies at the first hop, the segfault at the end
 * of the chain escapes the checker entirely. */

// EXPECT: null-deref
static void innermost(const char *p) { (void)*p; }

static void middle(const char *p) { innermost(p); }

static void outer(const char *p) { middle(p); }

int main(void) {
  char *p = (char *)malloc(4);
  outer(p);
  free(p);
  return 0;
}
