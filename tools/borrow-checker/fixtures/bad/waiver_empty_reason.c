#include "fixture_api.h"

/* A waiver with no justification after the marker is not a justification,
 * so it must not suppress the finding. */

// EXPECT: leak
int main(void) {
  char *p = (char *)malloc(4);
  /* borrow-check: allow(leak) -- */
  return p != 0;
}
