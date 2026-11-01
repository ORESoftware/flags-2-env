#include "flags2env_ores_bridge.h"
#include <assert.h>
#include <stddef.h>
#include <string.h>

/* Run with the canonical parser.c linked into this test executable. */
int main(void) {
  f2e_ores_result r = f2e_ores_parse(NULL, "[]");
  assert(r.status == 1 && r.data == NULL && r.length == 0);
  f2e_ores_free(&r);
  assert(r.status == 2 && r.data == NULL);
  f2e_ores_free(&r); /* repeated release is safe */
  r = f2e_ores_parse("relative.toml", "[]");
  assert(r.status == 1 && r.data == NULL);
  f2e_ores_free(&r);
  r = f2e_ores_parse("/nonexistent/flags2env-test.toml", NULL);
  assert(r.status == 1);
  f2e_ores_free(&r);
  r = f2e_ores_coerce(NULL, "{}");
  assert(r.status == 1);
  f2e_ores_free(&r);
  r = f2e_ores_coerce("relative.toml", "{}");
  assert(r.status == 1);
  f2e_ores_free(&r);
  f2e_ores_free(NULL);
  return 0;
}
