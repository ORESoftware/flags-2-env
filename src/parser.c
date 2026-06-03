#include "parser.h"

#include <ctype.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(__APPLE__)
#include <sys/sysctl.h>
#include <unistd.h>
#elif defined(__unix__)
#include <unistd.h>
#elif defined(_WIN32)
#include <shellapi.h>
#include <windows.h>
#endif

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
  char true_aliases[F2E_MAX_ALIASES][F2E_MAX_NAME];
  size_t true_alias_count;
  char false_aliases[F2E_MAX_ALIASES][F2E_MAX_NAME];
  size_t false_alias_count;
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

typedef struct {
  F2EBuffer errors;
  F2EBuffer warnings;
  size_t error_count;
  size_t warning_count;
  int failed;
} F2EAudit;

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

static char *f2e_empty_json_object(void);

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

static int f2e_add_alias_to_list(char aliases[][F2E_MAX_NAME], size_t *alias_count, const char *alias) {
  if (!alias || alias[0] == '\0') {
    return 0;
  }
  for (size_t i = 0; i < *alias_count; i++) {
    if (f2e_streq(aliases[i], alias)) {
      return 1;
    }
  }
  if (*alias_count >= F2E_MAX_ALIASES) {
    return 0;
  }
  f2e_strlcpy(aliases[*alias_count], alias, F2E_MAX_NAME);
  (*alias_count)++;
  return 1;
}

static int f2e_add_alias(F2EFlag *flag, const char *alias) {
  return f2e_add_alias_to_list(flag->aliases, &flag->alias_count, alias);
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

static const F2EFlag *f2e_find_flag_by_alias_const(const F2EConfig *config, const char *alias) {
  for (size_t i = 0; i < config->flag_count; i++) {
    const F2EFlag *flag = &config->flags[i];
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

static int f2e_parse_alias_list(char aliases[][F2E_MAX_NAME], size_t *alias_count, const char *value) {
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
    f2e_add_alias_to_list(aliases, alias_count, alias);
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

static int f2e_parse_aliases(F2EFlag *flag, const char *value) {
  return f2e_parse_alias_list(flag->aliases, &flag->alias_count, value);
}

static int f2e_parse_true_aliases(F2EFlag *flag, const char *value) {
  return f2e_parse_alias_list(flag->true_aliases, &flag->true_alias_count, value);
}

static int f2e_parse_false_aliases(F2EFlag *flag, const char *value) {
  return f2e_parse_alias_list(flag->false_aliases, &flag->false_alias_count, value);
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
    } else if (f2e_streq(key, "true_aliases")) {
      f2e_parse_true_aliases(current, value);
    } else if (f2e_streq(key, "false_aliases")) {
      f2e_parse_false_aliases(current, value);
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
  char dir[PATH_MAX];
  char home[PATH_MAX];
  const char *pwd = getenv("PWD");
  const char *home_env = getenv("HOME");

#if defined(_WIN32)
  if (GetCurrentDirectoryA(sizeof(dir), dir) == 0) {
    if (pwd && pwd[0] != '\0') {
      f2e_strlcpy(dir, pwd, sizeof(dir));
    } else {
      f2e_strlcpy(dir, ".", sizeof(dir));
    }
  }
#elif defined(__unix__) || defined(__APPLE__)
  if (!getcwd(dir, sizeof(dir))) {
    if (pwd && pwd[0] != '\0') {
      f2e_strlcpy(dir, pwd, sizeof(dir));
    } else {
      f2e_strlcpy(dir, ".", sizeof(dir));
    }
  }
#else
  if (pwd && pwd[0] != '\0') {
    f2e_strlcpy(dir, pwd, sizeof(dir));
  } else {
    f2e_strlcpy(dir, ".", sizeof(dir));
  }
#endif

  if (home_env && home_env[0] != '\0') {
    f2e_strlcpy(home, home_env, sizeof(home));
  } else {
    home[0] = '\0';
  }

  while (dir[0] != '\0') {
    size_t dir_len = strlen(dir);
    while (dir_len > 1 && (dir[dir_len - 1] == '/' || dir[dir_len - 1] == '\\')) {
      dir[--dir_len] = '\0';
    }

    if (home[0] != '\0') {
      size_t home_len = strlen(home);
      while (home_len > 1 && (home[home_len - 1] == '/' || home[home_len - 1] == '\\')) {
        home[--home_len] = '\0';
      }
      if (f2e_streq(dir, home)) {
        return NULL;
      }
    }

    const char suffix[] = "/.cli-flags.toml";
    char *candidate = (char *)malloc(dir_len + sizeof(suffix));
    if (!candidate) {
      return NULL;
    }
    memcpy(candidate, dir, dir_len);
    memcpy(candidate + dir_len, suffix, sizeof(suffix));

    FILE *file = fopen(candidate, "r");
    if (file) {
      fclose(file);
      return candidate;
    }
    free(candidate);

    char *slash = strrchr(dir, '/');
#if defined(_WIN32)
    char *backslash = strrchr(dir, '\\');
    if (!slash || (backslash && backslash > slash)) {
      slash = backslash;
    }
#endif
    if (!slash) {
      break;
    }
    if (slash == dir) {
      dir[1] = '\0';
      if (dir_len == 1) {
        break;
      }
    } else {
      *slash = '\0';
    }
  }

  return NULL;
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

static int f2e_audit_init(F2EAudit *audit) {
  memset(audit, 0, sizeof(*audit));
  if (!f2e_buffer_init(&audit->errors)) {
    return 0;
  }
  if (!f2e_buffer_init(&audit->warnings)) {
    free(audit->errors.data);
    memset(audit, 0, sizeof(*audit));
    return 0;
  }
  if (!f2e_buffer_append_char(&audit->errors, '[') || !f2e_buffer_append_char(&audit->warnings, '[')) {
    audit->failed = 1;
  }
  return 1;
}

static void f2e_audit_discard(F2EAudit *audit) {
  free(audit->errors.data);
  free(audit->warnings.data);
  memset(audit, 0, sizeof(*audit));
}

static void f2e_audit_add(F2EAudit *audit, int is_error, const char *format, ...) {
  if (!audit || audit->failed) {
    return;
  }

  char message[512];
  va_list args;
  va_start(args, format);
  vsnprintf(message, sizeof(message), format, args);
  va_end(args);

  F2EBuffer *target = is_error ? &audit->errors : &audit->warnings;
  size_t *count = is_error ? &audit->error_count : &audit->warning_count;
  if (*count > 0 && !f2e_buffer_append_char(target, ',')) {
    audit->failed = 1;
    return;
  }
  if (!f2e_buffer_append_json_string(target, message)) {
    audit->failed = 1;
    return;
  }
  (*count)++;
}

static char *f2e_audit_report(F2EAudit *audit, int *status_out) {
  if (!audit || audit->failed || !audit->errors.data || !audit->warnings.data) {
    if (status_out) {
      *status_out = 1;
    }
    if (audit) {
      f2e_audit_discard(audit);
    }
    const char failure_json[] = "{\"ok\":false,\"errorCount\":1,\"warningCount\":0,\"errors\":[\"audit allocation failed\"],\"warnings\":[]}";
    char *failed = (char *)malloc(sizeof(failure_json));
    if (failed) {
      f2e_strlcpy(failed, failure_json, sizeof(failure_json));
    }
    return failed;
  }

  if (!f2e_buffer_append_char(&audit->errors, ']') || !f2e_buffer_append_char(&audit->warnings, ']')) {
    if (status_out) {
      *status_out = 1;
    }
    f2e_audit_discard(audit);
    return f2e_empty_json_object();
  }

  F2EBuffer report;
  if (!f2e_buffer_init(&report)) {
    if (status_out) {
      *status_out = 1;
    }
    f2e_audit_discard(audit);
    return f2e_empty_json_object();
  }

  char counts[96];
  int ok = audit->error_count == 0;
  snprintf(counts, sizeof(counts), "{\"ok\":%s,\"errorCount\":%lu,\"warningCount\":%lu,\"errors\":",
           ok ? "true" : "false",
           (unsigned long)audit->error_count,
           (unsigned long)audit->warning_count);
  if (!f2e_buffer_append(&report, counts) ||
      !f2e_buffer_append(&report, audit->errors.data) ||
      !f2e_buffer_append(&report, ",\"warnings\":") ||
      !f2e_buffer_append(&report, audit->warnings.data) ||
      !f2e_buffer_append_char(&report, '}')) {
    free(report.data);
    if (status_out) {
      *status_out = 1;
    }
    f2e_audit_discard(audit);
    return f2e_empty_json_object();
  }

  if (status_out) {
    *status_out = ok ? 0 : 1;
  }
  f2e_audit_discard(audit);
  return report.data;
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

static int f2e_bool_value_alias(F2EFlag *flag, const char *value, const char **canonical) {
  if (!flag || !value) {
    return 0;
  }
  if (f2e_streq(value, "true")) {
    *canonical = "true";
    return 1;
  }
  if (f2e_streq(value, "false")) {
    *canonical = "false";
    return 1;
  }
  for (size_t i = 0; i < flag->true_alias_count; i++) {
    if (f2e_streq(flag->true_aliases[i], value)) {
      *canonical = "true";
      return 1;
    }
  }
  for (size_t i = 0; i < flag->false_alias_count; i++) {
    if (f2e_streq(flag->false_aliases[i], value)) {
      *canonical = "false";
      return 1;
    }
  }
  return 0;
}

static int f2e_try_set_bool_value(F2EFlag *flag, F2EPair *pairs, size_t pair_count, const char *value) {
  const char *canonical = NULL;
  if (!f2e_bool_value_alias(flag, value, &canonical)) {
    return 0;
  }
  f2e_set_pair(pairs, pair_count, flag->env, canonical);
  return 1;
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
      if (flag->type == F2E_TYPE_BOOL) {
        const char *canonical = NULL;
        if (f2e_bool_value_alias(flag, flag->default_value, &canonical)) {
          f2e_set_pair(pairs, pair_count, flag->env, canonical);
        } else {
          f2e_set_pair(pairs, pair_count, flag->env, flag->default_value);
        }
      } else {
        f2e_set_pair(pairs, pair_count, flag->env, flag->default_value);
      }
    }
  }
}

static int f2e_can_bundle_bool_shorts(F2EConfig *config, const char *shorts) {
  if (!shorts || shorts[0] == '\0') {
    return 0;
  }
  for (const char *cursor = shorts; *cursor; cursor++) {
    F2EFlag *flag = f2e_find_flag_by_short(config, *cursor);
    if (!flag || flag->env[0] == '\0' || flag->type != F2E_TYPE_BOOL) {
      return 0;
    }
  }
  return 1;
}

static void f2e_apply_bool_short_bundle(F2EConfig *config, F2EPair *pairs, size_t pair_count, const char *shorts) {
  for (const char *cursor = shorts; *cursor; cursor++) {
    F2EFlag *flag = f2e_find_flag_by_short(config, *cursor);
    if (flag && flag->env[0] != '\0' && flag->type == F2E_TYPE_BOOL) {
      f2e_set_pair(pairs, pair_count, flag->env, "true");
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
      f2e_try_set_bool_value(flag, pairs, pair_count, inline_value);
    } else if (*index + 1 < argc && strcmp(argv[*index + 1], "--") != 0 && !f2e_token_looks_like_known_option(config, argv[*index + 1]) && f2e_try_set_bool_value(flag, pairs, pair_count, argv[*index + 1])) {
      (*index)++;
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
  int has_inline_value = 0;
  if (*rest == '=') {
    has_inline_value = 1;
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

  if (has_inline_value) {
    f2e_try_set_bool_value(first, pairs, pair_count, rest);
    return;
  }

  if (*rest == '\0') {
    if (*index + 1 < argc && strcmp(argv[*index + 1], "--") != 0 && !f2e_token_looks_like_known_option(config, argv[*index + 1]) && f2e_try_set_bool_value(first, pairs, pair_count, argv[*index + 1])) {
      (*index)++;
      return;
    }
    f2e_set_pair(pairs, pair_count, first->env, "true");
    return;
  }

  if (f2e_can_bundle_bool_shorts(config, token + 1)) {
    f2e_apply_bool_short_bundle(config, pairs, pair_count, token + 1);
    return;
  }

  f2e_try_set_bool_value(first, pairs, pair_count, rest);
}

static const char *f2e_audit_flag_name(const F2EFlag *flag) {
  return flag && flag->name[0] != '\0' ? flag->name : "<unnamed>";
}

static void f2e_audit_bool_value_aliases(const F2EFlag *flag, F2EAudit *audit) {
  if (flag->type != F2E_TYPE_BOOL) {
    if (flag->true_alias_count > 0 || flag->false_alias_count > 0) {
      f2e_audit_add(audit, 0, "flags.%s declares boolean value aliases but type is not bool", f2e_audit_flag_name(flag));
    }
    return;
  }

  for (size_t i = 0; i < flag->true_alias_count; i++) {
    if (f2e_streq(flag->true_aliases[i], "false")) {
      f2e_audit_add(audit, 1, "flags.%s true_aliases contains canonical false", f2e_audit_flag_name(flag));
    } else if (f2e_streq(flag->true_aliases[i], "true")) {
      f2e_audit_add(audit, 0, "flags.%s true_aliases redundantly contains canonical true", f2e_audit_flag_name(flag));
    }
  }

  for (size_t i = 0; i < flag->false_alias_count; i++) {
    if (f2e_streq(flag->false_aliases[i], "true")) {
      f2e_audit_add(audit, 1, "flags.%s false_aliases contains canonical true", f2e_audit_flag_name(flag));
    } else if (f2e_streq(flag->false_aliases[i], "false")) {
      f2e_audit_add(audit, 0, "flags.%s false_aliases redundantly contains canonical false", f2e_audit_flag_name(flag));
    }
  }

  for (size_t i = 0; i < flag->true_alias_count; i++) {
    for (size_t j = 0; j < flag->false_alias_count; j++) {
      if (f2e_streq(flag->true_aliases[i], flag->false_aliases[j])) {
        f2e_audit_add(audit, 1, "flags.%s value alias \"%s\" appears in both true_aliases and false_aliases",
                      f2e_audit_flag_name(flag),
                      flag->true_aliases[i]);
      }
    }
  }
}

static void f2e_audit_config_semantics(const F2EConfig *config, F2EAudit *audit) {
  if (config->flag_count == 0) {
    f2e_audit_add(audit, 1, "no [flags.*] tables declared");
    return;
  }

  for (size_t i = 0; i < config->flag_count; i++) {
    const F2EFlag *flag = &config->flags[i];
    if (flag->env[0] == '\0') {
      f2e_audit_add(audit, 1, "flags.%s is missing env", f2e_audit_flag_name(flag));
    }
    if (flag->alias_count == 0) {
      f2e_audit_add(audit, 1, "flags.%s has no long aliases", f2e_audit_flag_name(flag));
    }
    for (size_t j = 0; j < flag->alias_count; j++) {
      const char *alias = flag->aliases[j];
      if (alias[0] == '\0') {
        f2e_audit_add(audit, 1, "flags.%s contains an empty alias", f2e_audit_flag_name(flag));
      } else if (alias[0] == '-') {
        f2e_audit_add(audit, 1, "flags.%s alias \"%s\" should not include leading dashes", f2e_audit_flag_name(flag), alias);
      }
    }
    if (flag->short_name != '\0' && (flag->short_name == '-' || isspace((unsigned char)flag->short_name))) {
      f2e_audit_add(audit, 1, "flags.%s has invalid short flag \"%c\"", f2e_audit_flag_name(flag), flag->short_name);
    }
    f2e_audit_bool_value_aliases(flag, audit);
  }

  for (size_t i = 0; i < config->flag_count; i++) {
    const F2EFlag *left = &config->flags[i];

    if (left->type == F2E_TYPE_BOOL) {
      for (size_t alias_index = 0; alias_index < left->alias_count; alias_index++) {
        char negated_alias[F2E_MAX_NAME + 3];
        snprintf(negated_alias, sizeof(negated_alias), "no-%s", left->aliases[alias_index]);
        const F2EFlag *clash = f2e_find_flag_by_alias_const(config, negated_alias);
        if (clash) {
          f2e_audit_add(audit, 1, "alias \"%s\" clashes with negated bool flag flags.%s",
                        negated_alias,
                        f2e_audit_flag_name(left));
        }
      }
    }

    for (size_t j = i + 1; j < config->flag_count; j++) {
      const F2EFlag *right = &config->flags[j];
      if (left->env[0] != '\0' && right->env[0] != '\0' && f2e_streq(left->env, right->env)) {
        f2e_audit_add(audit, 1, "flags.%s and flags.%s both map to env \"%s\"",
                      f2e_audit_flag_name(left),
                      f2e_audit_flag_name(right),
                      left->env);
      }
      if (left->short_name != '\0' && right->short_name != '\0' && left->short_name == right->short_name) {
        f2e_audit_add(audit, 1, "flags.%s and flags.%s both use short flag \"%c\"",
                      f2e_audit_flag_name(left),
                      f2e_audit_flag_name(right),
                      left->short_name);
      }
      for (size_t left_alias = 0; left_alias < left->alias_count; left_alias++) {
        for (size_t right_alias = 0; right_alias < right->alias_count; right_alias++) {
          if (f2e_streq(left->aliases[left_alias], right->aliases[right_alias])) {
            f2e_audit_add(audit, 1, "flags.%s and flags.%s both use alias \"%s\"",
                          f2e_audit_flag_name(left),
                          f2e_audit_flag_name(right),
                          left->aliases[left_alias]);
          }
        }
      }
    }
  }
}

static char *f2e_audit_error_report(const char *message, int *status_out) {
  F2EAudit audit;
  if (!f2e_audit_init(&audit)) {
    if (status_out) {
      *status_out = 1;
    }
    return f2e_empty_json_object();
  }
  f2e_audit_add(&audit, 1, "%s", message);
  return f2e_audit_report(&audit, status_out);
}

static char *f2e_audit_config_from_file_impl(const char *config_path, int *status_out) {
  F2EAudit audit;
  if (!f2e_audit_init(&audit)) {
    if (status_out) {
      *status_out = 1;
    }
    return f2e_empty_json_object();
  }

  F2EConfig *config = (F2EConfig *)malloc(sizeof(F2EConfig));
  if (!config) {
    f2e_audit_add(&audit, 1, "audit allocation failed");
    return f2e_audit_report(&audit, status_out);
  }

  if (!config_path || config_path[0] == '\0') {
    f2e_audit_add(&audit, 1, "config path is empty");
  } else if (!f2e_load_config(config_path, config)) {
    f2e_audit_add(&audit, 1, "could not read config \"%s\"", config_path);
  } else {
    f2e_audit_config_semantics(config, &audit);
  }

  free(config);
  return f2e_audit_report(&audit, status_out);
}

const char *f2e_version(void) {
  return F2E_VERSION;
}

char *f2e_audit_config_from_file(const char *config_path) {
  return f2e_audit_config_from_file_impl(config_path, NULL);
}

char *f2e_audit_config(void) {
  char *path = f2e_default_config_path();
  if (!path) {
    return f2e_audit_error_report("no usable .cli-flags.toml found before HOME", NULL);
  }
  char *result = f2e_audit_config_from_file(path);
  free(path);
  return result;
}

int f2e_audit_config_status_from_file(const char *config_path) {
  int status = 1;
  char *report = f2e_audit_config_from_file_impl(config_path, &status);
  free(report);
  return status;
}

int f2e_audit_config_status(void) {
  int status = 1;
  char *path = f2e_default_config_path();
  if (!path) {
    return 1;
  }
  char *report = f2e_audit_config_from_file_impl(path, &status);
  free(report);
  free(path);
  return status;
}

char *f2e_parse_from_file(const char *config_path, int argc, const char *const argv[]) {
  F2EConfig *config = (F2EConfig *)malloc(sizeof(F2EConfig));
  if (!config) {
    return f2e_empty_json_object();
  }

  if (!config_path || !f2e_load_config(config_path, config)) {
    free(config);
    return f2e_empty_json_object();
  }

  F2EPair *pairs = (F2EPair *)calloc(F2E_MAX_FLAGS, sizeof(F2EPair));
  if (!pairs) {
    free(config);
    return f2e_empty_json_object();
  }

  f2e_apply_defaults(config, pairs, F2E_MAX_FLAGS);

  for (int i = 0; i < argc; i++) {
    const char *token = argv[i];
    if (!token || token[0] != '-' || token[1] == '\0') {
      continue;
    }
    if (strcmp(token, "--") == 0) {
      break;
    }
    if (token[1] == '-') {
      f2e_apply_long_arg(config, pairs, F2E_MAX_FLAGS, token, &i, argc, argv);
    } else {
      f2e_apply_short_arg(config, pairs, F2E_MAX_FLAGS, token, &i, argc, argv);
    }
  }

  char *json = f2e_pairs_to_json(pairs, F2E_MAX_FLAGS);
  free(pairs);
  free(config);
  if (!json) {
    json = f2e_empty_json_object();
  }
  return json;
}

char *f2e_parse(int argc, const char *const argv[]) {
  char *path = f2e_default_config_path();
  if (!path) {
    return f2e_empty_json_object();
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

static char *f2e_empty_json_object(void) {
  char *empty = (char *)malloc(3);
  if (empty) {
    f2e_strlcpy(empty, "{}", 3);
  }
  return empty;
}

#if defined(__linux__)
static int f2e_read_process_argv(char ***items, int *count) {
  FILE *file = fopen("/proc/self/cmdline", "rb");
  if (!file) {
    return 0;
  }

  size_t len = 0;
  size_t cap = 256;
  char *data = (char *)malloc(cap);
  if (!data) {
    fclose(file);
    return 0;
  }

  int ch;
  while ((ch = fgetc(file)) != EOF) {
    if (len + 1 >= cap) {
      cap *= 2;
      char *grown = (char *)realloc(data, cap);
      if (!grown) {
        free(data);
        fclose(file);
        return 0;
      }
      data = grown;
    }
    data[len++] = (char)ch;
  }
  fclose(file);

  int argv_cap = 0;
  *items = NULL;
  *count = 0;
  size_t start = 0;
  for (size_t i = 0; i <= len; i++) {
    if (i == len || data[i] == '\0') {
      if (i > start && !f2e_json_array_append(items, count, &argv_cap, data + start)) {
        f2e_free_json_items(*items, *count);
        *items = NULL;
        *count = 0;
        free(data);
        return 0;
      }
      start = i + 1;
    }
  }

  free(data);
  return *count > 0;
}
#elif defined(__APPLE__)
static int f2e_read_process_argv(char ***items, int *count) {
  int mib[3] = {CTL_KERN, KERN_PROCARGS2, getpid()};
  size_t size = 0;
  if (sysctl(mib, 3, NULL, &size, NULL, 0) != 0 || size == 0) {
    return 0;
  }

  char *data = (char *)malloc(size);
  if (!data) {
    return 0;
  }
  if (sysctl(mib, 3, data, &size, NULL, 0) != 0) {
    free(data);
    return 0;
  }

  int argc = 0;
  memcpy(&argc, data, sizeof(argc));
  if (argc <= 0) {
    free(data);
    return 0;
  }

  char *cursor = data + sizeof(argc);
  char *end = data + size;
  while (cursor < end && *cursor != '\0') {
    cursor++;
  }
  while (cursor < end && *cursor == '\0') {
    cursor++;
  }

  int argv_cap = 0;
  *items = NULL;
  *count = 0;
  for (int i = 0; i < argc && cursor < end; i++) {
    if (!f2e_json_array_append(items, count, &argv_cap, cursor)) {
      f2e_free_json_items(*items, *count);
      *items = NULL;
      *count = 0;
      free(data);
      return 0;
    }
    while (cursor < end && *cursor != '\0') {
      cursor++;
    }
    while (cursor < end && *cursor == '\0') {
      cursor++;
    }
  }

  free(data);
  return *count > 0;
}
#elif defined(_WIN32)
static int f2e_read_process_argv(char ***items, int *count) {
  int argc = 0;
  LPWSTR *wide_argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  if (!wide_argv || argc <= 0) {
    return 0;
  }

  int argv_cap = 0;
  *items = NULL;
  *count = 0;
  for (int i = 0; i < argc; i++) {
    int utf8_len = WideCharToMultiByte(CP_UTF8, 0, wide_argv[i], -1, NULL, 0, NULL, NULL);
    if (utf8_len <= 0) {
      continue;
    }
    char *value = (char *)malloc((size_t)utf8_len);
    if (!value) {
      f2e_free_json_items(*items, *count);
      LocalFree(wide_argv);
      return 0;
    }
    WideCharToMultiByte(CP_UTF8, 0, wide_argv[i], -1, value, utf8_len, NULL, NULL);
    if (!f2e_json_array_append(items, count, &argv_cap, value)) {
      free(value);
      f2e_free_json_items(*items, *count);
      LocalFree(wide_argv);
      return 0;
    }
    free(value);
  }

  LocalFree(wide_argv);
  return *count > 0;
}
#else
static int f2e_read_process_argv(char ***items, int *count) {
  *items = NULL;
  *count = 0;
  return 0;
}
#endif

char *f2e_parse_process_from_file(const char *config_path) {
  char **items = NULL;
  int count = 0;
  if (!f2e_read_process_argv(&items, &count)) {
    return f2e_parse_from_file(config_path, 0, NULL);
  }

  char *result = f2e_parse_from_file(config_path, count, (const char *const *)items);
  f2e_free_json_items(items, count);
  return result;
}

char *f2e_parse_process(void) {
  char *path = f2e_default_config_path();
  if (!path) {
    return f2e_empty_json_object();
  }
  char *result = f2e_parse_process_from_file(path);
  free(path);
  return result;
}

char *f2e_parse_json_argv_from_file(const char *config_path, const char *argv_json) {
  char **items = NULL;
  int count = 0;
  if (!argv_json || !f2e_parse_json_argv_items(argv_json, &items, &count)) {
    f2e_free_json_items(items, count);
    return f2e_empty_json_object();
  }

  char *result = f2e_parse_from_file(config_path, count, (const char *const *)items);
  f2e_free_json_items(items, count);
  return result;
}

char *f2e_parse_json_argv(const char *argv_json) {
  char *path = f2e_default_config_path();
  if (!path) {
    return f2e_empty_json_object();
  }
  char *result = f2e_parse_json_argv_from_file(path, argv_json);
  free(path);
  return result;
}

void f2e_free(char *value) {
  free(value);
}
