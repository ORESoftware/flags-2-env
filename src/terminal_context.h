#ifndef F2E_TERMINAL_CONTEXT_H
#define F2E_TERMINAL_CONTEXT_H

#include "parser.h"

#ifdef __cplusplus
extern "C" {
#endif

#define F2E_TERMINAL_CONTEXT_VERSION 1

/*
 * Returns a heap-allocated JSON object describing the current process I/O and
 * terminal environment. The report is observational: it never changes process
 * environment variables or command output. Release it with f2e_free().
 */
char *f2e_terminal_context_json(void) F2E_OWNED_RESULT;

/*
 * Returns the same context as a string-only environment map using reserved
 * F2E_CONTEXT_* keys. This is suitable for explicit shell/export adapters and
 * remains opt-in. Release it with f2e_free().
 */
char *f2e_terminal_context_env_json(void) F2E_OWNED_RESULT;

/* Returns a stable family name such as bash, zsh, fish, powershell, cmd, or unknown. */
const char *f2e_terminal_shell_family(void);

#ifdef __cplusplus
}
#endif

#endif
