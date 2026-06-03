#include "lib.h"

#include <stdio.h>
#include <string.h>
#include <unistd.h>

int main(void) {
  if (chdir("tests/fixtures/nested/deeper") != 0) {
    perror("chdir");
    return 1;
  }

  const char *argv[] = {"app", "--debug=t", "--port", "8181"};
  F2EMap parsed = {0};
  if (!f2e_client_parse(4, argv, &parsed)) {
    return 1;
  }

  const char *debug = f2e_map_get(&parsed, "DEBUG");
  const char *port = f2e_map_get(&parsed, "PORT");
  const char *color = f2e_map_get(&parsed, "COLOR");
  int ok = debug && strcmp(debug, "true") == 0 && port && strcmp(port, "8181") == 0 && color && strcmp(color, "true") == 0;
  f2e_map_free(&parsed);
  return ok ? 0 : 1;
}
