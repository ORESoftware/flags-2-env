#ifndef FLAGS2ENV_ORES_BRIDGE_H
#define FLAGS2ENV_ORES_BRIDGE_H
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Oreslang FFI boundary. Returned bytes are owned by the caller and must
 * be released with f2e_ores_free. Never assume a null return means {}. */
typedef struct {
  char *data;
  size_t length;
  int status;
} f2e_ores_result;
/* status: 0 success; 1 invalid input; 2 native parser failure.
 * JSON bytes are UTF-8 and include no terminating NUL in length. */
f2e_ores_result f2e_ores_parse(const char *absolute_config_path,
                                const char *argv_json);
f2e_ores_result f2e_ores_coerce(const char *absolute_config_path,
                                 const char *values_json);
void f2e_ores_free(f2e_ores_result *result);
#ifdef __cplusplus
}
#endif
#endif
