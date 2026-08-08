#include "fixture_api.h"

/* An intentional leak with a justified waiver must not fail the build. */
int main(void) {
  const char *argv[] = {"app", "--help"};
  /* borrow-check: allow(leak) -- handed to the OS at process exit */
  char *json = fx_parse(2, argv);
  return json != 0;
}
