#include "fixture_api.h"

// EXPECT: double-free
int main(void) {
  const char *argv[] = {"app", "--help"};
  char *json = fx_parse(2, argv);
  if (!json) {
    return 1;
  }
  fx_free(json);
  fx_free(json);
  return 0;
}
