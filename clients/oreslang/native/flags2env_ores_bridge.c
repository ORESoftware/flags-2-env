#include "flags2env_ores_bridge.h"
#include "../../../src/parser.h"
#include <string.h>

static int absolute_path(const char *path) {
  if (!path || !path[0]) return 0;
#ifdef _WIN32
  return ((path[0] >= 'A' && path[0] <= 'Z') ||
          (path[0] >= 'a' && path[0] <= 'z')) &&
          path[1] == ':' && (path[2] == '/' || path[2] == '\\');
#else
  return path[0] == '/';
#endif
}
static f2e_ores_result invalid(void) {
  f2e_ores_result r = {0, 0, 1};
  return r;
}
static f2e_ores_result wrap(char *ptr) {
  f2e_ores_result r = {0, 0, 2};
  if (ptr) {
    r.data = ptr;
    r.length = strlen(ptr);
    r.status = 0;
  }
  return r;
}
f2e_ores_result f2e_ores_parse(const char *config, const char *argv) {
  if (!absolute_path(config) || !argv) return invalid();
  return wrap(f2e_parse_json_argv_from_file(config, argv));
}
f2e_ores_result f2e_ores_coerce(const char *config, const char *values) {
  if (!absolute_path(config) || !values) return invalid();
  return wrap(f2e_coerce_json_from_file(config, values));
}
void f2e_ores_free(f2e_ores_result *r) {
  if (!r) return;
  if (r->data) f2e_free(r->data);
  r->data = 0;
  r->length = 0;
  r->status = 2;
}
