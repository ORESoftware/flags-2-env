#include "fixture_api.h"

// EXPECT: lost-realloc
char *grow(size_t next) {
  char *data = (char *)malloc(16);
  if (!data) {
    return 0;
  }
  data = (char *)realloc(data, next);
  return data;
}
