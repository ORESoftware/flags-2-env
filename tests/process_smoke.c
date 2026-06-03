#include "parser.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void) {
  char *json = f2e_parse_process_from_file("tests/fixtures/.cli-flags.toml");
  if (!json) {
    fputs("expected process parse JSON, got NULL\n", stderr);
    return 1;
  }

  const char *expected = "{\"PORT\":\"7777\",\"DEBUG\":\"true\",\"COLOR\":\"true\"}";
  if (strcmp(json, expected) != 0) {
    fprintf(stderr, "expected %s\nactual   %s\n", expected, json);
    f2e_free(json);
    return 1;
  }

  f2e_free(json);
  return 0;
}
