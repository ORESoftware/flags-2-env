#ifndef F2E_BORROW_FIXTURE_API_H
#define F2E_BORROW_FIXTURE_API_H

#include <stddef.h>
#include <stdlib.h>
#include <string.h>

/* Mirror of the public ownership macros in src/parser.h; the checker reads
 * these declarations textually as the contract for the fixture programs. */
#define F2E_WARN_UNUSED_RESULT
#define F2E_OWNED_RESULT F2E_WARN_UNUSED_RESULT
#define F2E_TAKES_OWNED_ARG_1

char *fx_parse(int argc, const char *const argv[]) F2E_OWNED_RESULT;
char *fx_render(const char *name) F2E_OWNED_RESULT;
void fx_free(char *value) F2E_TAKES_OWNED_ARG_1;
const char *fx_peek(const char *value);

#endif
