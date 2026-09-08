#include "parser.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static size_t decode_utf8(const unsigned char *value, size_t available, uint32_t *codepoint) {
  if (!value || available == 0 || !codepoint) {
    return 0;
  }
  if (value[0] < 0x80) {
    *codepoint = value[0];
    return 1;
  }

  size_t count = value[0] < 0xe0 ? 2u : value[0] < 0xf0 ? 3u : 4u;
  uint32_t decoded = value[0] & (count == 2 ? 0x1fu : count == 3 ? 0x0fu : 0x07u);
  if (count > available || value[0] < 0xc2 || value[0] > 0xf4) {
    return 0;
  }
  for (size_t i = 1; i < count; i++) {
    if ((value[i] & 0xc0) != 0x80) {
      return 0;
    }
    decoded = (decoded << 6) | (uint32_t)(value[i] & 0x3f);
  }
  if ((count == 2 && decoded < 0x80) || (count == 3 && decoded < 0x800) ||
      (count == 4 && decoded < 0x10000) || decoded > 0x10ffff ||
      (decoded >= 0xd800 && decoded <= 0xdfff)) {
    return 0;
  }
  *codepoint = decoded;
  return count;
}

static size_t cell_width(uint32_t codepoint) {
  if ((codepoint >= 0x0300 && codepoint <= 0x036f) || codepoint == 0x200d ||
      (codepoint >= 0xfe00 && codepoint <= 0xfe0f)) {
    return 0;
  }
  if ((codepoint >= 0x2e80 && codepoint <= 0xa4cf) ||
      (codepoint >= 0x1f300 && codepoint <= 0x1faff)) {
    return 2;
  }
  return 1;
}

static int line_has_width(const char *line, size_t byte_len, size_t expected) {
  size_t offset = 0;
  size_t columns = 0;
  while (offset < byte_len) {
    uint32_t codepoint = 0;
    size_t consumed = decode_utf8((const unsigned char *)line + offset,
                                  byte_len - offset,
                                  &codepoint);
    if (consumed == 0) {
      fprintf(stderr, "help output split or emitted invalid UTF-8 at byte %zu\n", offset);
      return 0;
    }
    columns += cell_width(codepoint);
    offset += consumed;
  }
  if (columns != expected) {
    fprintf(stderr, "help line used %zu display cells instead of %zu: %.*s\n",
            columns,
            expected,
            (int)byte_len,
            line);
    return 0;
  }
  return 1;
}

int main(void) {
  const size_t expected_columns = 48;
  char *table = f2e_help_table_from_file("tests/help-unicode/.cli-flags.toml",
                                         "flags2env-🌍",
                                         (int)expected_columns);
  if (!table) {
    fprintf(stderr, "failed to render Unicode help fixture\n");
    return 1;
  }

  int ok = strstr(table, "café") != NULL && strstr(table, "東京") != NULL &&
           strstr(table, "🧭") != NULL && strstr(table, "é") != NULL;
  const char *cursor = table;
  while (ok && *cursor) {
    const char *newline = strchr(cursor, '\n');
    size_t byte_len = newline ? (size_t)(newline - cursor) : strlen(cursor);
    ok = line_has_width(cursor, byte_len, expected_columns);
    cursor += byte_len + (newline ? 1u : 0u);
  }

  f2e_free(table);
  return ok ? 0 : 1;
}
