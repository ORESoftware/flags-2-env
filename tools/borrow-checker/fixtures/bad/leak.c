#include "fixture_api.h"

// EXPECT: leak
int main(void) {
  const char *argv[] = {"app", "--help"};
  char *json = fx_parse(2, argv);
  return json != 0;
}
