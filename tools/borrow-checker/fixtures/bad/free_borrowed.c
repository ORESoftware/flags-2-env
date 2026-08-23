#include "fixture_api.h"

// EXPECT: free-borrowed
void render_and_discard(char *label) {
  fx_free(label);
}
