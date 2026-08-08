#include "fixture_api.h"

// EXPECT: null-deref
char first_byte(void) {
  char *json = fx_render("demo");
  char head = json[0];
  fx_free(json);
  return head;
}
