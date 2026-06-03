#include "parser.h"

#include <stdio.h>

int main(int argc, const char *const argv[]) {
  char *json = f2e_parse(argc, argv);
  if (!json) {
    fputs("{}\n", stdout);
    return 1;
  }
  fputs(json, stdout);
  fputc('\n', stdout);
  f2e_free(json);
  return 0;
}
