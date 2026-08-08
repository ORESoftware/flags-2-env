#include "fixture_api.h"

// EXPECT: return-local-addr
char *label(void) {
  char buffer[32];
  char *view = buffer;
  buffer[0] = 'x';
  return view;
}
