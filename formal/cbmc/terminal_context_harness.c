#include <assert.h>
#include <stddef.h>

#include "../../src/terminal_context.c"

extern void __CPROVER_assume(_Bool condition);
extern char nondet_char(void);
extern size_t nondet_size_t(void);

/* Case-insensitive equality is reflexive, symmetric, and reads neither
 * string past its terminator (bounds/pointer checks are implicit). */
void harness_ascii_equal_ci(void) {
  char left[4];
  char right[4];

  for (size_t i = 0; i < sizeof(left) - 1; i++) {
    left[i] = nondet_char();
    right[i] = nondet_char();
  }
  left[sizeof(left) - 1] = '\0';
  right[sizeof(right) - 1] = '\0';

  assert(f2e_ascii_equal_ci(left, left) == 1);
  assert(f2e_ascii_equal_ci(left, right) == f2e_ascii_equal_ci(right, left));
  assert(f2e_ascii_equal_ci(NULL, left) == 0);
  assert(f2e_ascii_equal_ci(left, NULL) == 0);
}

/* Every non-empty string contains itself, and the scan cannot run past
 * either buffer for arbitrary contents. */
void harness_ascii_contains_ci(void) {
  char value[4];

  for (size_t i = 0; i < sizeof(value) - 1; i++) {
    value[i] = nondet_char();
  }
  value[sizeof(value) - 1] = '\0';

  int contains_self = f2e_ascii_contains_ci(value, value);
  if (value[0] != '\0') {
    assert(contains_self == 1);
  } else {
    assert(contains_self == 0);
  }
  assert(f2e_ascii_contains_ci(NULL, value) == 0);
  assert(f2e_ascii_contains_ci(value, NULL) == 0);
}

/* The basename view always points inside the original buffer and never
 * contains a path separator. */
void harness_path_basename(void) {
  char path[5];

  for (size_t i = 0; i < sizeof(path) - 1; i++) {
    path[i] = nondet_char();
  }
  path[sizeof(path) - 1] = '\0';

  const char *base = f2e_path_basename(path);
  assert(base >= path);
  assert(base <= path + sizeof(path) - 1);
  for (const char *cursor = base; *cursor; cursor++) {
    assert(*cursor != '/');
    assert(*cursor != '\\');
  }
  assert(f2e_path_basename(NULL)[0] == '\0');
}

/* Truthiness is total and boolean over arbitrary short inputs, and the
 * documented falsey spellings stay falsey. */
void harness_value_truthy(void) {
  char value[4];

  for (size_t i = 0; i < sizeof(value) - 1; i++) {
    value[i] = nondet_char();
  }
  value[sizeof(value) - 1] = '\0';

  int truthy = f2e_value_truthy(value);
  assert(truthy == 0 || truthy == 1);
  assert(f2e_value_truthy(NULL) == 0);
  assert(f2e_value_truthy("") == 0);
  assert(f2e_value_truthy("0") == 0);
  assert(f2e_value_truthy("false") == 0);
  assert(f2e_value_truthy("no") == 0);
  assert(f2e_value_truthy("off") == 0);
  assert(f2e_value_truthy("never") == 0);
  assert(f2e_value_truthy("1") == 1);
}

/* Column parsing returns 0 or a value inside the documented [20, 10000]
 * clamp, for every input the type can carry. */
void harness_parse_columns(void) {
  char value[8];

  for (size_t i = 0; i < sizeof(value) - 1; i++) {
    char digit = nondet_char();
    __CPROVER_assume(digit >= '0' && digit <= '9');
    value[i] = digit;
  }
  value[sizeof(value) - 1] = '\0';

  unsigned int columns = f2e_parse_columns(value);
  assert(columns == 0 || (columns >= 20 && columns <= 10000));
  assert(f2e_parse_columns(NULL) == 0);
  assert(f2e_parse_columns("") == 0);
  assert(f2e_parse_columns("19") == 0);
  assert(f2e_parse_columns("10001") == 0);
  assert(f2e_parse_columns("80") == 80);
}
