#include "fixture_api.h"

/* An intentional leak with a justified waiver must not fail the build. The
 * waiver sits on the line where the diagnostic is reported. */
int main(void) {
  const char *argv[] = {"app", "--help"};
  char *json = fx_parse(2, argv);
  /* borrow-check: allow(leak) -- handed to the OS at process exit */
  return json != 0;
}
