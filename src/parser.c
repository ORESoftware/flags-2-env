#include "parser.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

#define F2E_MAX_FLAGS 256
#define F2E_MAX_ALIASES 24
#define F2E_MAX_NAME 96
#define F2E_MAX_ENV 128
#define F2E_MAX_VALUE 1024
#define F2E_MAX_LINE 4096

typedef enum {
  F2E_TYPE_STRING = 0,
  F2E_TYPE_BOOL = 1
} F2EValueType;

typedef struct {
  char name[F2E_MAX_NAME];
  char env[F2E_MAX_ENV];
  char aliases[F2E_MAX_ALIASES][F2E_MAX_NAME];
  size_t alias_count;
  char short_name;
  F2EValueType type;
  int has_default;
  char default_value[F2E_MAX_VALUE];
} F2EFlag;

typedef struct {
  F2EFlag flags[F2E_MAX_FLAGS];
  size_t flag_count;
} F2EConfig;

typedef struct {
  char key[F2E_MAX_ENV];
  char value[F2E_MAX_VALUE];
  int set;
} F2EPair;

typedef struct {
  char *data;
  size_t len;
  size_t cap;
} F2EBuffer;

static size_t f2e_strlcpy(char *dst, const char *src, size_t dst_size) {
  size_t src_len = src ? strlen(src) : 0;
  if (dst_size > 0) {
    size_t copy_len = src_len >= dst_size ? dst_size - 1 : src_len;
    if (copy_len > 0 && src) {
      memcpy(dst, src, copy_len);
    }
    dst[copy_len] = '\0';
  }
  return src_len;
}

static int f2e_streq(const char *a, const char *b) {
  return strcmp(a, b) == 0;
}

static char *f2e_trim_left(char *value) {
  while (*value && isspace((unsigned char)*value)) {
    value++;
  }
  return value;
}

static void f2e_trim_right(char *value) {
  size_t len = strlen(value);
  while (len > 0 && isspace((unsigned char)value[len - 1])) {
    value[len - 1] = '\0';
    len--;
  }
}

static char *f2e_trim(char *value) {
  char *left = f2e_trim_left(value);
  f2e_trim_right(left);
  return left;
}

static void f2e_strip_comment(char *line) {
  int in_quote = 0;
  int escaped = 0;
  for (char *cursor = line; *cursor; cursor++) {
    if (escaped) {
      escaped = 0;
      continue;
    }
    if (*cursor == '\\' && in_quote) {
      escaped = 1;
      continue;
    }
    if (*cursor == '"') {
      in_quote = !in_quote;
      continue;
    }
    if (*cursor == '#' && !in_quote) {
      *cursor = '\0';
      return;
    }
  }
}

static int f2e_parse_quoted_string(const char *input, char *out, size_t out_size) {
  const char *cursor = f2e_trim_left((char *)input);
  size_t len = 0;
  if (*cursor != '"') {
    return 0;
  }
  cursor++;
  while (*cursor && *cursor != '"') {
    char ch = *cursor++;
    if (ch == '\\' && *cursor) {
      char escaped = *cursor++;
      switch (escaped) {
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
        default:
          ch = escaped;
          break;
      }
    }
    if (len + 1 < out_size) {
      out[len++] = ch;
    }
  }
  if (*cursor != '"') {
    return 0;
  }
  if (out_size > 0) {
    out[len] = '\0';
  }
  return 1;
}

static int f2e_parse_bare_value(const char *input, char *out, size_t out_size) {
  char tmp[F2E_MAX_VALUE];
  f2e_strlcpy(tmp, input, sizeof(tmp));
  char *trimmed = f2e_trim(tmp);
  if (*trimmed == '"') {
    return f2e_parse_quoted_string(trimmed, out, out_size);
  }
  f2e_strlcpy(out, trimmed, out_size);
  return out[0] != '\0';
}

static int f2e_add_alias(F2EFlag *flag, const char *alias) {
  if (!alias || alias[0] == '\0') {
    return 0;
  }
  for (size_t i = 0; i < flag->alias_count; i++) {
    if (f2e_streq(flag->aliases[i], alias)) {
      return 1;
    }
  }
  if (flag->alias_count >= F2E_MAX_ALIASES) {
    return 0;
  }
  f2e_strlcpy(flag->aliases[flag->alias_count], alias, sizeof(flag->aliases[0]));
  flag->alias_count++;
  return 1;
}

static F2EFlag *f2e_add_flag(F2EConfig *config, const char *name) {
  if (config->flag_count >= F2E_MAX_FLAGS) {
    return NULL;
  }
  F2EFlag *flag = &config->flags[config->flag_count++];
  memset(flag, 0, sizeof(*flag));
  flag->type = F2E_TYPE_STRING;
  f2e_strlcpy(flag->name, name, sizeof(flag->name));
  f2e_add_alias(flag, name);
  return flag;
}

static F2EFlag *f2e_find_flag_by_alias(F2EConfig *config, const char *alias) {
  for (size_t i = 0; i < config->flag_count; i++) {
    F2EFlag *flag = &config->flags[i];
    for (size_t j = 0; j < flag->alias_count; j++) {
      if (f2e_streq(flag->aliases[j], alias)) {
        return flag;
      }
    }
  }
  return NULL;
}

static F2EFlag *f2e_find_flag_by_short(F2EConfig *config, char short_name) {
  for (size_t i = 0; i < config->flag_count; i++) {
    if (config->flags[i].short_name == short_name) {
      return &config->flags[i];
    }
  }
  return NULL;
}

static int f2e_parse_aliases(F2EFlag *flag, const char *value) {
  const char *cursor = f2e_trim_left((char *)value);
  if (*cursor != '[') {
    return 0;
  }
  cursor++;
  while (*cursor) {
    cursor = f2e_trim_left((char *)cursor);
    if (*cursor == ']') {
      return 1;
    }
    char alias[F2E_MAX_NAME];
    if (!f2e_parse_quoted_string(cursor, alias, sizeof(alias))) {
      return 0;
    }
    f2e_add_alias(flag, alias);
    cursor++;
    int escaped = 0;
    while (*cursor) {
      if (escaped) {
        escaped = 0;
      } else if (*cursor == '\\') {
        escaped = 1;
      } else if (*cursor == '"') {
        cursor++;
        break;
      }
      cursor++;
    }
    cursor = f2e_trim_left((char *)cursor);
    if (*cursor == ',') {
      cursor++;
    }
  }
  return 0;
}

static int f2e_parse_type(const char *value, F2EValueType *type) {
  char parsed[F2E_MAX_VALUE];
  if (!f2e_parse_bare_value(value, parsed, sizeof(parsed))) {
    return 0;
  }
  if (f2e_streq(parsed, "bool") || f2e_streq(parsed, "boolean") || f2e_streq(parsed, "flag")) {
    *type = F2E_TYPE_BOOL;
    return 1;
  }
  if (f2e_streq(parsed, "string") || f2e_streq(parsed, "value")) {
    *type = F2E_TYPE_STRING;
    return 1;
  }
  return 0;
}

static int f2e_load_config(const char *config_path, F2EConfig *config) {
  memset(config, 0, sizeof(*config));

  FILE *file = fopen(config_path, "r");
  if (!file) {
    return 0;
  }

  F2EFlag *current = NULL;
  char line[F2E_MAX_LINE];
  while (fgets(line, sizeof(line), file)) {
    f2e_strip_comment(line);
    char *trimmed = f2e_trim(line);
    if (trimmed[0] == '\0') {
      continue;
    }

    if (trimmed[0] == '[') {
      char *end = strchr(trimmed, ']');
      if (!end) {
        current = NULL;
        continue;
      }
      *end = '\0';
      char *table = f2e_trim(trimmed + 1);
      const char prefix[] = "flags.";
      if (strncmp(table, prefix, sizeof(prefix) - 1) == 0) {
        char *name = f2e_trim(table + sizeof(prefix) - 1);
        current = f2e_add_flag(config, name);
      } else {
        current = NULL;
      }
      continue;
    }

    if (!current) {
      continue;
    }

    char *eq = strchr(trimmed, '=');
    if (!eq) {
      continue;
    }
    *eq = '\0';
    char *key = f2e_trim(trimmed);
    char *value = f2e_trim(eq + 1);

    if (f2e_streq(key, "env")) {
      char parsed[F2E_MAX_ENV];
      if (f2e_parse_bare_value(value, parsed, sizeof(parsed))) {
        f2e_strlcpy(current->env, parsed, sizeof(current->env));
      }
    } else if (f2e_streq(key, "aliases")) {
      f2e_parse_aliases(current, value);
    } else if (f2e_streq(key, "short")) {
      char parsed[F2E_MAX_VALUE];
      if (f2e_parse_bare_value(value, parsed, sizeof(parsed)) && parsed[0] != '\0') {
        current->short_name = parsed[0];
      }
    } else if (f2e_streq(key, "type")) {
      f2e_parse_type(value, &current->type);
    } else if (f2e_streq(key, "default")) {
      char parsed[F2E_MAX_VALUE];
      if (f2e_parse_bare_value(value, parsed, sizeof(parsed))) {
        current->has_default = 1;
        f2e_strlcpy(current->default_value, parsed, sizeof(current->default_value));
      }
    }
  }

  fclose(file);
  return 1;
}

static char *f2e_default_config_path(void) {
  const char *pwd = getenv("PWD");
  char base[PATH_MAX];
  if (pwd && pwd[0] != '\0') {
    f2e_strlcpy(base, pwd, sizeof(base));
  } else {
    base[0] = '.';
    base[1] = '\0';
  }

  size_t len = strlen(base);
  const char suffix[] = "/.cli-flags.toml";
  char *path = (char *)malloc(len + sizeof(suffix));
  if (!path) {
    return NULL;
  }
  memcpy(path, base, len);
  memcpy(path + len, suffix, sizeof(suffix));
  return path;
}

static F2EPair *f2e_find_pair(F2EPair *pairs, size_t pair_count, const char *key) {
  for (size_t i = 0; i < pair_count; i++) {
    if (pairs[i].set && f2e_streq(pairs[i].key, key)) {
      return &pairs[i];
    }
  }
  return NULL;
}

static void f2e_set_pair(F2EPair *pairs, size_t pair_count, const char *key, const char *value) {
  if (!key || key[0] == '\0') {
    return;
  }
  F2EPair *pair = f2e_find_pair(pairs, pair_count, key);
  if (!pair) {
    for (size_t i = 0; i < pair_count; i++) {
      if (!pairs[i].set) {
        pair = &pairs[i];
        pair->set = 1;
        f2e_strlcpy(pair->key, key, sizeof(pair->key));
        break;
      }
    }
  }
  if (pair) {
    f2e_strlcpy(pair->value, value ? value : "", sizeof(pair->value));
  }
}

static int f2e_buffer_init(F2EBuffer *buffer) {
  buffer->cap = 128;
  buffer->len = 0;
  buffer->data = (char *)malloc(buffer->cap);
  if (!buffer->data) {
    return 0;
  }
  buffer->data[0] = '\0';
  return 1;
}

static int f2e_buffer_reserve(F2EBuffer *buffer, size_t extra) {
  if (buffer->len + extra + 1 <= buffer->cap) {
    return 1;
  }
  size_t next = buffer->cap;
  while (buffer->len + extra + 1 > next) {
    next *= 2;
  }
  char *data = (char *)realloc(buffer->data, next);
  if (!data) {
    return 0;
  }
  buffer->data = data;
  buffer->cap = next;
  return 1;
}

static int f2e_buffer_append_char(F2EBuffer *buffer, char ch) {
  if (!f2e_buffer_reserve(buffer, 1)) {
    return 0;
  }
  buffer->data[buffer->len++] = ch;
  buffer->data[buffer->len] = '\0';
  return 1;
}

static int f2e_buffer_append(F2EBuffer *buffer, const char *value) {
  size_t len = strlen(value);
  if (!f2e_buffer_reserve(buffer, len)) {
    return 0;
  }
  memcpy(buffer->data + buffer->len, value, len);
  buffer->len += len;
  buffer->data[buffer->len] = '\0';
  return 1;
}

static int f2e_buffer_append_json_string(F2EBuffer *buffer, const char *value) {
  if (!f2e_buffer_append_char(buffer, '"')) {
    return 0;
  }
  for (const unsigned char *cursor = (const unsigned char *)value; *cursor; cursor++) {
    switch (*cursor) {
      case '"':
        if (!f2e_buffer_append(buffer, "\\\"")) {
          return 0;
        }
        break;
      case '\\':
        if (!f2e_buffer_append(buffer, "\\\\")) {
          return 0;
        }
        break;
      case '\b':
        if (!f2e_buffer_append(buffer, "\\b")) {
          return 0;
        }
        break;
      case '\f':
        if (!f2e_buffer_append(buffer, "\\f")) {
          return 0;
        }
        break;
      case '\n':
        if (!f2e_buffer_append(buffer, "\\n")) {
          return 0;
        }
        break;
      case '\r':
        if (!f2e_buffer_append(buffer, "\\r")) {
          return 0;
        }
        break;
      case '\t':
        if (!f2e_buffer_append(buffer, "\\t")) {
          return 0;
        }
        break;
      default:
        if (*cursor < 0x20) {
          char escaped[7];
          snprintf(escaped, sizeof(escaped), "\\u%04x", *cursor);
          if (!f2e_buffer_append(buffer, escaped)) {
            return 0;
          }
        } else if (!f2e_buffer_append_char(buffer, (char)*cursor)) {
          return 0;
        }
        break;
    }
  }
  return f2e_buffer_append_char(buffer, '"');
}

static char *f2e_pairs_to_json(F2EPair *pairs, size_t pair_count) {
  F2EBuffer buffer;
  if (!f2e_buffer_init(&buffer)) {
    return NULL;
  }
  f2e_buffer_append_char(&buffer, '{');
  int wrote = 0;
  for (size_t i = 0; i < pair_count; i++) {
    if (!pairs[i].set) {
      continue;
    }
    if (wrote) {
      f2e_buffer_append_char(&buffer, ',');
    }
    f2e_buffer_append_json_string(&buffer, pairs[i].key);
    f2e_buffer_append_char(&buffer, ':');
    f2e_buffer_append_json_string(&buffer, pairs[i].value);
    wrote = 1;
  }
  f2e_buffer_append_char(&buffer, '}');
  return buffer.data;
}

static int f2e_token_looks_like_known_option(F2EConfig *config, const char *token) {
  if (!token || token[0] != '-' || token[1] == '\0') {
    return 0;
  }
  if (token[1] == '-') {
    const char *name = token + 2;
    if (strncmp(name, "no-", 3) == 0) {
      name += 3;
    }
    char copy[F2E_MAX_NAME];
    f2e_strlcpy(copy, name, sizeof(copy));
    char *eq = strchr(copy, '=');
    if (eq) {
      *eq = '\0';
    }
    return f2e_find_flag_by_alias(config, copy) != NULL;
  }
  return f2e_find_flag_by_short(config, token[1]) != NULL;
}

static void f2e_apply_defaults(F2EConfig *config, F2EPair *pairs, size_t pair_count) {
  for (size_t i = 0; i < config->flag_count; i++) {
    F2EFlag *flag = &config->flags[i];
    if (flag->env[0] != '\0' && flag->has_default) {
      f2e_set_pair(pairs, pair_count, flag->env, flag->default_value);
    }
  }
}

static void f2e_apply_long_arg(F2EConfig *config, F2EPair *pairs, size_t pair_count, const char *token, int *index, int argc, const char *const argv[]) {
  char name[F2E_MAX_NAME];
  char inline_value[F2E_MAX_VALUE];
  int has_inline_value = 0;
  int negated = 0;

  const char *raw = token + 2;
  if (strncmp(raw, "no-", 3) == 0) {
    negated = 1;
    raw += 3;
  }

  f2e_strlcpy(name, raw, sizeof(name));
  char *eq = strchr(name, '=');
  if (eq) {
    *eq = '\0';
    f2e_strlcpy(inline_value, eq + 1, sizeof(inline_value));
    has_inline_value = 1;
  }

  F2EFlag *flag = f2e_find_flag_by_alias(config, name);
  if (!flag || flag->env[0] == '\0') {
    return;
  }

  if (flag->type == F2E_TYPE_BOOL) {
    if (negated) {
      f2e_set_pair(pairs, pair_count, flag->env, "false");
    } else if (has_inline_value) {
      f2e_set_pair(pairs, pair_count, flag->env, inline_value);
    } else {
      f2e_set_pair(pairs, pair_count, flag->env, "true");
    }
    return;
  }

  if (has_inline_value) {
    f2e_set_pair(pairs, pair_count, flag->env, inline_value);
  } else if (*index + 1 < argc && strcmp(argv[*index + 1], "--") != 0 && !f2e_token_looks_like_known_option(config, argv[*index + 1])) {
    (*index)++;
    f2e_set_pair(pairs, pair_count, flag->env, argv[*index]);
  } else {
    f2e_set_pair(pairs, pair_count, flag->env, "true");
  }
}

static void f2e_apply_short_arg(F2EConfig *config, F2EPair *pairs, size_t pair_count, const char *token, int *index, int argc, const char *const argv[]) {
  if (token[1] == '\0') {
    return;
  }

  char short_name = token[1];
  F2EFlag *first = f2e_find_flag_by_short(config, short_name);
  if (!first || first->env[0] == '\0') {
    return;
  }

  const char *rest = token + 2;
  if (*rest == '=') {
    rest++;
  }

  if (first->type == F2E_TYPE_STRING) {
    if (*rest) {
      f2e_set_pair(pairs, pair_count, first->env, rest);
    } else if (*index + 1 < argc && strcmp(argv[*index + 1], "--") != 0 && !f2e_token_looks_like_known_option(config, argv[*index + 1])) {
      (*index)++;
      f2e_set_pair(pairs, pair_count, first->env, argv[*index]);
    } else {
      f2e_set_pair(pairs, pair_count, first->env, "true");
    }
    return;
  }

  if (*rest == '\0') {
    f2e_set_pair(pairs, pair_count, first->env, "true");
    return;
  }

  for (const char *cursor = token + 1; *cursor; cursor++) {
    F2EFlag *flag = f2e_find_flag_by_short(config, *cursor);
    if (!flag || flag->env[0] == '\0' || flag->type != F2E_TYPE_BOOL) {
      return;
    }
    f2e_set_pair(pairs, pair_count, flag->env, "true");
  }
}

const char *f2e_version(void) {
  return F2E_VERSION;
}

char *f2e_parse_from_file(const char *config_path, int argc, const char *const argv[]) {
  F2EConfig config;
  if (!config_path || !f2e_load_config(config_path, &config)) {
    char *empty = (char *)malloc(3);
    if (empty) {
      f2e_strlcpy(empty, "{}", 3);
    }
    return empty;
  }

  F2EPair pairs[F2E_MAX_FLAGS];
  memset(pairs, 0, sizeof(pairs));
  f2e_apply_defaults(&config, pairs, F2E_MAX_FLAGS);

  for (int i = 0; i < argc; i++) {
    const char *token = argv[i];
    if (!token || token[0] != '-' || token[1] == '\0') {
      continue;
    }
    if (strcmp(token, "--") == 0) {
      break;
    }
    if (token[1] == '-') {
      f2e_apply_long_arg(&config, pairs, F2E_MAX_FLAGS, token, &i, argc, argv);
    } else {
      f2e_apply_short_arg(&config, pairs, F2E_MAX_FLAGS, token, &i, argc, argv);
    }
  }

  char *json = f2e_pairs_to_json(pairs, F2E_MAX_FLAGS);
  if (!json) {
    json = (char *)malloc(3);
    if (json) {
      f2e_strlcpy(json, "{}", 3);
    }
  }
  return json;
}

char *f2e_parse(int argc, const char *const argv[]) {
  char *path = f2e_default_config_path();
  if (!path) {
    return NULL;
  }
  char *result = f2e_parse_from_file(path, argc, argv);
  free(path);
  return result;
}

static int f2e_json_array_append(char ***items, int *count, int *cap, const char *value) {
  if (*count >= *cap) {
    int next = *cap == 0 ? 8 : *cap * 2;
    char **grown = (char **)realloc(*items, sizeof(char *) * (size_t)next);
    if (!grown) {
      return 0;
    }
    *items = grown;
    *cap = next;
  }
  char *copy = (char *)malloc(strlen(value) + 1);
  if (!copy) {
    return 0;
  }
  strcpy(copy, value);
  (*items)[(*count)++] = copy;
  return 1;
}

static int f2e_parse_json_string_token(const char **cursor_ref, char *out, size_t out_size) {
  const char *cursor = f2e_trim_left((char *)*cursor_ref);
  size_t len = 0;
  if (*cursor != '"') {
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
    if (len + 1 < out_size) {
      out[len++] = ch;
    }
  }
  if (*cursor != '"') {
    return 0;
  }
  cursor++;
  if (out_size > 0) {
    out[len] = '\0';
  }
  *cursor_ref = cursor;
  return 1;
}

static int f2e_parse_json_argv_items(const char *argv_json, char ***items, int *count) {
  const char *cursor = f2e_trim_left((char *)argv_json);
  int cap = 0;
  *items = NULL;
  *count = 0;

  if (!argv_json || *cursor != '[') {
    return 0;
  }
  cursor++;

  while (*cursor) {
    cursor = f2e_trim_left((char *)cursor);
    if (*cursor == ']') {
      return 1;
    }

    char value[F2E_MAX_VALUE];
    if (!f2e_parse_json_string_token(&cursor, value, sizeof(value))) {
      return 0;
    }
    if (!f2e_json_array_append(items, count, &cap, value)) {
      return 0;
    }

    cursor = f2e_trim_left((char *)cursor);
    if (*cursor == ',') {
      cursor++;
      continue;
    }
    if (*cursor == ']') {
      return 1;
    }
    return 0;
  }
  return 0;
}

static void f2e_free_json_items(char **items, int count) {
  if (!items) {
    return;
  }
  for (int i = 0; i < count; i++) {
    free(items[i]);
  }
  free(items);
}

char *f2e_parse_json_argv_from_file(const char *config_path, const char *argv_json) {
  char **items = NULL;
  int count = 0;
  if (!argv_json || !f2e_parse_json_argv_items(argv_json, &items, &count)) {
    f2e_free_json_items(items, count);
    char *empty = (char *)malloc(3);
    if (empty) {
      f2e_strlcpy(empty, "{}", 3);
    }
    return empty;
  }

  char *result = f2e_parse_from_file(config_path, count, (const char *const *)items);
  f2e_free_json_items(items, count);
  return result;
}

char *f2e_parse_json_argv(const char *argv_json) {
  char *path = f2e_default_config_path();
  if (!path) {
    return NULL;
  }
  char *result = f2e_parse_json_argv_from_file(path, argv_json);
  free(path);
  return result;
}

void f2e_free(char *value) {
  free(value);
}
