#ifndef F2E_PARSER_H
#define F2E_PARSER_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define F2E_VERSION "0.1.0"

const char *f2e_version(void);

/*
 * Parses argv using PWD/.cli-flags.toml and returns a heap-allocated JSON
 * object string. Call f2e_free() with the returned pointer.
 */
char *f2e_parse(int argc, const char *const argv[]);

/*
 * Parses argv using an explicit TOML config path and returns a heap-allocated
 * JSON object string. Call f2e_free() with the returned pointer.
 */
char *f2e_parse_from_file(const char *config_path, int argc, const char *const argv[]);

/*
 * FFI-friendly entrypoint: argv_json must be a JSON array of strings.
 * Returns a heap-allocated JSON object string. Call f2e_free().
 */
char *f2e_parse_json_argv(const char *argv_json);

/*
 * FFI-friendly entrypoint with an explicit config path.
 */
char *f2e_parse_json_argv_from_file(const char *config_path, const char *argv_json);

void f2e_free(char *value);

#ifdef __cplusplus
}
#endif

#endif
