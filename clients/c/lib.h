#ifndef F2E_CLIENT_C_LIB_H
#define F2E_CLIENT_C_LIB_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
  char *key;
  char *value;
} F2EMapEntry;

typedef struct {
  F2EMapEntry *entries;
  size_t length;
} F2EMap;

int f2e_client_parse(int argc, const char *const argv[], F2EMap *out);
int f2e_client_parse_from_file(const char *config_path, int argc, const char *const argv[], F2EMap *out);
int f2e_client_apply_envp(char *const envp[], int argc, const char *const argv[], F2EMap *out);
int f2e_map_set(F2EMap *map, const char *key, const char *value);
int f2e_map_overlay(F2EMap *target, const F2EMap *source);
const char *f2e_map_get(const F2EMap *map, const char *key);
void f2e_map_free(F2EMap *map);

#ifdef __cplusplus
}
#endif

#endif
