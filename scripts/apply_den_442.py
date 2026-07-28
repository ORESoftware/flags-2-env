#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PARSER = ROOT / "src" / "parser.c"
RUN = ROOT / "tests" / "run.sh"

original = PARSER.read_text(encoding="utf-8")
duplicates = [
    path
    for path in (ROOT / "clients").rglob("parser.c")
    if path.read_text(encoding="utf-8") == original
]

text = original
text = text.replace(
    "#define F2E_MAX_LINE 4096\n",
    "#define F2E_MAX_LINE 4096\n#define F2E_MAX_LOGICAL_LINE (F2E_MAX_LINE * 32)\n",
    1,
)

marker = '''static void f2e_strip_comment(char *line) {
  int in_quote = 0;
  int escaped = 0;
  for (char *cursor = line; *cursor; cursor++) {
    if (escaped) {
      escaped = 0;
      continue;
    }
    if (*cursor == '\\\\' && in_quote) {
      escaped = 1;
      continue;
    }
    if (*cursor == '"') {
      in_quote = !in_quote;
      continue;
    }
    if (*cursor == '#' && !in_quote) {
      *cursor = '\\0';
      return;
    }
  }
}
'''
insert = marker + '''
static int f2e_array_value_is_complete(const char *value) {
  const char *cursor = f2e_trim_left((char *)value);
  if (*cursor != '[') {
    return 1;
  }

  int depth = 0;
  int in_quote = 0;
  int escaped = 0;
  for (; *cursor; cursor++) {
    if (escaped) {
      escaped = 0;
      continue;
    }
    if (*cursor == '\\\\' && in_quote) {
      escaped = 1;
      continue;
    }
    if (*cursor == '"') {
      in_quote = !in_quote;
      continue;
    }
    if (in_quote) {
      continue;
    }
    if (*cursor == '[') {
      depth++;
    } else if (*cursor == ']') {
      depth--;
      if (depth <= 0) {
        return 1;
      }
    }
  }
  return 0;
}

static int f2e_append_logical_config_line(char *target,
                                          size_t target_size,
                                          const char *fragment) {
  size_t used = strlen(target);
  size_t fragment_len = strlen(fragment);
  size_t separator = used > 0 ? 1 : 0;
  if (used + separator + fragment_len + 1 > target_size) {
    return 0;
  }
  if (separator) {
    target[used++] = '\\n';
  }
  memcpy(target + used, fragment, fragment_len + 1);
  return 1;
}
'''
if text.count(marker) != 1:
    raise SystemExit("strip-comment marker mismatch")
text = text.replace(marker, insert, 1)

old_loop = '''  char line[F2E_MAX_LINE];
  while (fgets(line, sizeof(line), file)) {
    f2e_strip_comment(line);
    char *trimmed = f2e_trim(line);
    if (trimmed[0] == '\\0') {
      continue;
    }

    if (trimmed[0] == '[') {
'''
new_loop = '''  char line[F2E_MAX_LINE];
  char logical_line[F2E_MAX_LOGICAL_LINE];
  while (fgets(line, sizeof(line), file)) {
    f2e_strip_comment(line);
    char *trimmed = f2e_trim(line);
    if (trimmed[0] == '\\0') {
      continue;
    }

    f2e_strlcpy(logical_line, trimmed, sizeof(logical_line));
    char *logical_eq = strchr(logical_line, '=');
    if (logical_eq) {
      char *logical_value = f2e_trim(logical_eq + 1);
      while (*logical_value == '[' && !f2e_array_value_is_complete(logical_value)) {
        if (!fgets(line, sizeof(line), file)) {
          break;
        }
        f2e_strip_comment(line);
        char *continuation = f2e_trim(line);
        if (continuation[0] == '\\0') {
          continue;
        }
        if (!f2e_append_logical_config_line(logical_line,
                                            sizeof(logical_line),
                                            continuation)) {
          fclose(file);
          return 0;
        }
        logical_eq = strchr(logical_line, '=');
        logical_value = f2e_trim(logical_eq + 1);
      }
    }
    trimmed = f2e_trim(logical_line);

    if (trimmed[0] == '[') {
'''
if text.count(old_loop) != 1:
    raise SystemExit("config loop marker mismatch")
text = text.replace(old_loop, new_loop, 1)

PARSER.write_text(text, encoding="utf-8")
for duplicate in duplicates:
    duplicate.write_text(text, encoding="utf-8")

run = RUN.read_text(encoding="utf-8")
needle = "printf 'flags2env tests passed\\n'\n"
block = '''MULTILINE_ARRAY_DIR="$ROOT_DIR/tests/multiline-arrays"
MULTILINE_ARRAY_CONFIG="$MULTILINE_ARRAY_DIR/.cli-flags.toml"
actual="$("$CLI" audit "$MULTILINE_ARRAY_CONFIG")"
expected='{"ok":true,"errorCount":0,"warningCount":0,"errors":[],"warnings":[]}'
if [ "$actual" != "$expected" ]; then
  printf 'Expected clean multiline-array audit: %s\\nActual:                                %s\\n' "$expected" "$actual" >&2
  exit 1
fi

actual="$(cd "$MULTILINE_ARRAY_DIR" && "$CLI" multiline --operation-mode fast --without-color)"
expected='{"MULTILINE_COMMAND":"","MODE":"fast","COLOR":"false"}'
if [ "$actual" != "$expected" ]; then
  printf 'Expected multiline global aliases: %s\\nActual:                            %s\\n' "$expected" "$actual" >&2
  exit 1
fi

actual="$(cd "$MULTILINE_ARRAY_DIR" && "$CLI" multiline ship --destination production --yes-color)"
expected='{"MULTILINE_COMMAND":"deploy","MODE":"safe","COLOR":"true","TARGET":"production"}'
if [ "$actual" != "$expected" ]; then
  printf 'Expected multiline command aliases: %s\\nActual:                             %s\\n' "$expected" "$actual" >&2
  exit 1
fi

multiline_help="$(cd "$MULTILINE_ARRAY_DIR" && COLUMNS=132 "$CLI" multiline --help)"
case "$multiline_help" in
  *'| Option(s)'*'| Env'*'| Description'*'More help: https://example.com/multiline'*)
    ;;
  *)
    printf 'Unexpected multiline-array help table:\\n%s\\n' "$multiline_help" >&2
    exit 1
    ;;
esac
case "$multiline_help" in
  *'| Type'*|*'| Default'*)
    printf 'Multiline help.columns should omit type/default:\\n%s\\n' "$multiline_help" >&2
    exit 1
    ;;
esac

INVALID_MULTILINE_TYPE_CONFIG="$ROOT_DIR/tests/audit-invalid-multiline-type/.cli-flags.toml"
set +e
actual="$("$CLI" audit "$INVALID_MULTILINE_TYPE_CONFIG")"
status=$?
set -e
expected='{"ok":false,"errorCount":1,"warningCount":0,"errors":["env.ignore must be a list of env var names"],"warnings":[]}'
if [ "$status" -eq 0 ] || [ "$actual" != "$expected" ]; then
  printf 'Expected invalid multiline element audit failure:\\n%s\\nActual status: %s\\nActual: %s\\n' "$expected" "$status" "$actual" >&2
  exit 1
fi

INVALID_MULTILINE_UNCLOSED_CONFIG="$ROOT_DIR/tests/audit-invalid-multiline-unclosed/.cli-flags.toml"
set +e
actual="$("$CLI" audit "$INVALID_MULTILINE_UNCLOSED_CONFIG")"
status=$?
set -e
expected='{"ok":false,"errorCount":1,"warningCount":0,"errors":["help.columns must be a list of supported table column names"],"warnings":[]}'
if [ "$status" -eq 0 ] || [ "$actual" != "$expected" ]; then
  printf 'Expected unclosed multiline array audit failure:\\n%s\\nActual status: %s\\nActual: %s\\n' "$expected" "$status" "$actual" >&2
  exit 1
fi

'''
if run.count(needle) != 1:
    raise SystemExit("tests/run.sh terminator mismatch")
run = run.replace(needle, block + needle, 1)
RUN.write_text(run, encoding="utf-8")

print(f"patched canonical parser and {len(duplicates)} byte-identical client copies")
