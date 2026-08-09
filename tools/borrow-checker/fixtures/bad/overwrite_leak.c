#include "fixture_api.h"

// EXPECT: overwrite-leak
int main(void) {
  char *json = fx_render("one");
  if (!json) {
    return 1;
  }
  json = fx_render("two");
  if (!json) {
    return 1;
  }
  fx_free(json);
  return 0;
}
