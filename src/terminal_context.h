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

/*
 * The individual facts behind the JSON report, for callers that need one
 * predicate rather than a document -- notably the parser, which enforces
 * [flags.*] requires_tty and must agree with this detection rather than
 * running its own.
 *
 * `stream` is "stdin", "stdout", or "stderr"; anything else returns 0. The
 * F2E_FORCE_STDIN_TTY / F2E_FORCE_STDOUT_TTY / F2E_FORCE_STDERR_TTY overrides
 * apply, so tests can pin the answer without allocating a pty.
 */
int f2e_terminal_stream_is_tty(const char *stream) F2E_WARN_UNUSED_RESULT;

/*
 * True when a prompt can actually be answered: terminal stdin and stderr,
 * outside CI, and not TERM=dumb. Stdout may be redirected, because data can be
 * piped while the prompt stays on stderr.
 */
int f2e_terminal_can_prompt(void) F2E_WARN_UNUSED_RESULT;

#ifdef __cplusplus
}
#endif

#endif
