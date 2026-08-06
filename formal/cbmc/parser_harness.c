#include <assert.h>
#include <stddef.h>

#include "../../src/parser.c"

extern void __CPROVER_assume(_Bool condition);
extern char nondet_char(void);
extern size_t nondet_size_t(void);

void harness_size_bounds(void) {
  size_t a = nondet_size_t();
  size_t b = nondet_size_t();
  size_t minimum = f2e_size_min(a, b);
  size_t maximum = f2e_size_max(a, b);

  assert(minimum <= a);
  assert(minimum <= b);
  assert(minimum == a || minimum == b);
  assert(maximum >= a);
  assert(maximum >= b);
  assert(maximum == a || maximum == b);
}

void harness_strlcpy(void) {
  char source[8];
  char destination[8];
  size_t source_len = nondet_size_t();
  size_t destination_size = nondet_size_t();

  __CPROVER_assume(source_len < sizeof(source));
  __CPROVER_assume(destination_size <= sizeof(destination));

  for (size_t i = 0; i < sizeof(source); i++) {
    source[i] = nondet_char();
  }
  for (size_t i = 0; i < source_len; i++) {
    __CPROVER_assume(source[i] != '\0');
  }
  source[source_len] = '\0';

  size_t reported_len = f2e_strlcpy(destination, source, destination_size);
  assert(reported_len == source_len);

  if (destination_size > 0) {
    size_t copied_len =
        source_len < destination_size ? source_len : destination_size - 1;
    assert(destination[copied_len] == '\0');
    for (size_t i = 0; i < copied_len; i++) {
      assert(destination[i] == source[i]);
    }
  }
}

void harness_option_shape(void) {
  char token[3];

  token[0] = nondet_char();
  token[1] = nondet_char();
  token[2] = '\0';
  int looks_like_option = f2e_token_looks_like_option(token);
  assert(looks_like_option == (token[0] == '-' && token[1] != '\0'));
}

void harness_coercion_slot_bounds(void) {
  size_t flag_count = nondet_size_t();
  size_t command_count = nondet_size_t();

  __CPROVER_assume(flag_count <= F2E_MAX_FLAGS);
  __CPROVER_assume(command_count <= F2E_MAX_COMMANDS);

  size_t slots = f2e_coerce_slot_count_values(flag_count, command_count);
  assert(slots >= flag_count);
  assert(slots >= command_count);
  assert(slots == flag_count + command_count + 1);
  assert(slots <= F2E_MAX_FLAGS + F2E_MAX_COMMANDS + 1);
}
