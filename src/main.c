#include "parser.h"

#include <stdio.h>
#include <string.h>

int main(int argc, const char *const argv[]) {
  if (argc >= 2 && (strcmp(argv[1], "audit") == 0 || strcmp(argv[1], "--audit") == 0)) {
    const char *config_path = argc >= 3 ? argv[2] : NULL;
    char *report = config_path ? f2e_audit_config_from_file(config_path) : f2e_audit_config();
    int status = config_path ? f2e_audit_config_status_from_file(config_path) : f2e_audit_config_status();
    if (!report) {
      fputs("{\"ok\":false,\"errors\":[\"audit failed\"]}\n", stdout);
      return 1;
    }
    fputs(report, stdout);
    fputc('\n', stdout);
    f2e_free(report);
    return status;
  }

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
