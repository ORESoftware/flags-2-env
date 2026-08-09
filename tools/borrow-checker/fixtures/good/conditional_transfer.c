#include "fixture_api.h"

struct entry {
  char *key;
  char *value;
};

struct table {
  struct entry *entries;
  size_t length;
};

/* Stores both pointers on success, stores nothing on failure: the caller
 * conditionally transfers ownership, exactly like realloc's argument. */
static int append(struct table *table, char *key, char *value) {
  struct entry *grown = (struct entry *)realloc(
      table->entries, sizeof(struct entry) * (table->length + 1));
  if (!grown) {
    return 0;
  }
  table->entries = grown;
  table->entries[table->length].key = key;
  table->entries[table->length].value = value;
  table->length++;
  return 1;
}

static char *copy_text(const char *text) {
  size_t len = strlen(text);
  char *copy = (char *)malloc(len + 1);
  if (!copy) {
    return 0;
  }
  memcpy(copy, text, len + 1);
  return copy;
}

/* The canonical grow-and-insert: free on the failure path, hand off on the
 * success path, and neither direction may be diagnosed. */
int insert(struct table *table, const char *key, const char *value) {
  char *key_copy = copy_text(key);
  char *value_copy = copy_text(value);
  if (!key_copy || !value_copy) {
    free(key_copy);
    free(value_copy);
    return 0;
  }
  if (!append(table, key_copy, value_copy)) {
    free(key_copy);
    free(value_copy);
    return 0;
  }
  return 1;
}

/* The realloc grow loop: the old pointer is freed on failure and
 * overwritten on success, and neither is an error. */
int grow_buffer(struct table *table, char **data_io, size_t next) {
  (void)table;
  char *data = *data_io;
  char *grown = (char *)realloc(data, next);
  if (!grown) {
    free(data);
    return 0;
  }
  data = grown;
  *data_io = data;
  return 1;
}
