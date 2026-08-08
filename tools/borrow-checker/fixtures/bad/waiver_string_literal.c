#include "fixture_api.h"

/* A string literal that merely quotes the waiver syntax must not silence
 * a real finding: waivers are a comment construct, not a text match. */

// EXPECT: leak
int main(void) {
  char *p = (char *)malloc(4);
  const char *doc = "borrow-check: allow(leak) -- quoting, not waiving";
  (void)doc;
  return p != 0;
}
