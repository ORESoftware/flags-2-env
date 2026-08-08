#include "fixture_api.h"

// EXPECT: use-after-free
size_t use(void) {
  char *json = fx_render("demo");
  if (!json) {
    return 0;
  }
  fx_free(json);
  return strlen(json);
}
