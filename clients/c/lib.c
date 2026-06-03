#include "lib.h"

#include "../../src/parser.h"

#include <stdlib.h>
#include <string.h>

static char *f2e_client_strdup(const char *value) {
  size_t len = strlen(value);
  char *copy = (char *)malloc(len + 1);
  if (!copy) {
    return NULL;
  }
  memcpy(copy, value, len + 1);
  return copy;
}

static const char *f2e_client_skip_ws(const char *cursor) {
  while (*cursor == ' ' || *cursor == '\n' || *cursor == '\r' || *cursor == '\t') {
    cursor++;
  }
  return cursor;
}

static int f2e_client_parse_json_string(const char **cursor_ref, char **out) {
  const char *cursor = f2e_client_skip_ws(*cursor_ref);
  size_t cap = 32;
  size_t len = 0;
  char *value = (char *)malloc(cap);
  if (!value) {
    return 0;
  }
  if (*cursor != '"') {
    free(value);
    return 0;
  }
  cursor++;
  while (*cursor && *cursor != '"') {
    char ch = *cursor++;
    if (ch == '\\' && *cursor) {
      char escaped = *cursor++;
      switch (escaped) {
        case 'b':
          ch = '\b';
          break;
        case 'f':
          ch = '\f';
          break;
        case 'n':
          ch = '\n';
          break;
        case 'r':
          ch = '\r';
          break;
        case 't':
          ch = '\t';
          break;
        case '"':
        case '\\':
        case '/':
          ch = escaped;
          break;
        case 'u':
          if (cursor[0] && cursor[1] && cursor[2] && cursor[3]) {
            ch = '?';
            cursor += 4;
          }
          break;
        default:
          ch = escaped;
          break;
      }
    }
    if (len + 2 > cap) {
      cap *= 2;
      char *grown = (char *)realloc(value, cap);
      if (!grown) {
        free(value);
        return 0;
      }
      value = grown;
    }
    value[len++] = ch;
  }
  if (*cursor != '"') {
    free(value);
    return 0;
  }
  cursor++;
  value[len] = '\0';
  *cursor_ref = cursor;
  *out = value;
  return 1;
}

static int f2e_client_append(F2EMap *map, char *key, char *value) {
  F2EMapEntry *grown = (F2EMapEntry *)realloc(map->entries, sizeof(F2EMapEntry) * (map->length + 1));
  if (!grown) {
    return 0;
  }
  map->entries = grown;
  map->entries[map->length].key = key;
  map->entries[map->length].value = value;
  map->length++;
  return 1;
}

int f2e_map_set(F2EMap *map, const char *key, const char *value) {
  if (!map || !key) {
    return 0;
  }

  for (size_t i = 0; i < map->length; i++) {
    if (strcmp(map->entries[i].key, key) == 0) {
      char *copy = f2e_client_strdup(value ? value : "");
      if (!copy) {
        return 0;
      }
      free(map->entries[i].value);
      map->entries[i].value = copy;
      return 1;
    }
  }

  char *key_copy = f2e_client_strdup(key);
  char *value_copy = f2e_client_strdup(value ? value : "");
  if (!key_copy || !value_copy) {
    free(key_copy);
    free(value_copy);
    return 0;
  }
  if (!f2e_client_append(map, key_copy, value_copy)) {
    free(key_copy);
    free(value_copy);
    return 0;
  }
  return 1;
}

int f2e_map_overlay(F2EMap *target, const F2EMap *source) {
  if (!target || !source) {
    return 0;
  }
  for (size_t i = 0; i < source->length; i++) {
    if (!f2e_map_set(target, source->entries[i].key, source->entries[i].value)) {
      return 0;
    }
  }
  return 1;
}

static int f2e_map_from_envp(char *const envp[], F2EMap *out) {
  out->entries = NULL;
  out->length = 0;
  if (!envp) {
    return 1;
  }

  for (size_t i = 0; envp[i]; i++) {
    const char *entry = envp[i];
    const char *eq = strchr(entry, '=');
    if (!eq) {
      continue;
    }
    size_t key_len = (size_t)(eq - entry);
    char *key = (char *)malloc(key_len + 1);
    if (!key) {
      return 0;
    }
    memcpy(key, entry, key_len);
    key[key_len] = '\0';
    if (!f2e_map_set(out, key, eq + 1)) {
      free(key);
      return 0;
    }
    free(key);
  }
  return 1;
}

static int f2e_client_map_from_json(const char *json, F2EMap *out) {
  const char *cursor = f2e_client_skip_ws(json);
  out->entries = NULL;
  out->length = 0;

  if (*cursor != '{') {
    return 0;
  }
  cursor++;

  while (*cursor) {
    cursor = f2e_client_skip_ws(cursor);
    if (*cursor == '}') {
      return 1;
    }

    char *key = NULL;
    char *value = NULL;
    if (!f2e_client_parse_json_string(&cursor, &key)) {
      return 0;
    }
    cursor = f2e_client_skip_ws(cursor);
    if (*cursor != ':') {
      free(key);
      return 0;
    }
    cursor++;
    if (!f2e_client_parse_json_string(&cursor, &value)) {
      free(key);
      return 0;
    }
    if (!f2e_client_append(out, key, value)) {
      free(key);
      free(value);
      return 0;
    }
    cursor = f2e_client_skip_ws(cursor);
    if (*cursor == ',') {
      cursor++;
      continue;
    }
    if (*cursor == '}') {
      return 1;
    }
    return 0;
  }
  return 0;
}

int f2e_client_parse_from_file(const char *config_path, int argc, const char *const argv[], F2EMap *out) {
  char *json = f2e_parse_from_file(config_path, argc, argv);
  if (!json) {
    return 0;
  }
  int ok = f2e_client_map_from_json(json, out);
  f2e_free(json);
  if (!ok) {
    f2e_map_free(out);
  }
  return ok;
}

int f2e_client_parse(int argc, const char *const argv[], F2EMap *out) {
  char *json = f2e_parse(argc, argv);
  if (!json) {
    return 0;
  }
  int ok = f2e_client_map_from_json(json, out);
  f2e_free(json);
  if (!ok) {
    f2e_map_free(out);
  }
  return ok;
}

int f2e_client_apply_envp(char *const envp[], int argc, const char *const argv[], F2EMap *out) {
  F2EMap parsed = {0};
  out->entries = NULL;
  out->length = 0;

  if (!f2e_map_from_envp(envp, out)) {
    f2e_map_free(out);
    return 0;
  }
  if (!f2e_client_parse(argc, argv, &parsed)) {
    f2e_map_free(out);
    return 0;
  }
  int ok = f2e_map_overlay(out, &parsed);
  f2e_map_free(&parsed);
  if (!ok) {
    f2e_map_free(out);
  }
  return ok;
}

const char *f2e_map_get(const F2EMap *map, const char *key) {
  if (!map || !key) {
    return NULL;
  }
  for (size_t i = 0; i < map->length; i++) {
    if (strcmp(map->entries[i].key, key) == 0) {
      return map->entries[i].value;
    }
  }
  return NULL;
}

void f2e_map_free(F2EMap *map) {
  if (!map) {
    return;
  }
  for (size_t i = 0; i < map->length; i++) {
    free(map->entries[i].key);
    free(map->entries[i].value);
  }
  free(map->entries);
  map->entries = NULL;
  map->length = 0;
}
