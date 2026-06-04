#include "parser.h"

#include <ctype.h>
#include <errno.h>
#include <limits.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <direct.h>
#define F2E_MKDIR(path) _mkdir(path)
#else
#include <sys/stat.h>
#include <sys/types.h>
#define F2E_MKDIR(path) mkdir(path, 0755)
#endif

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

static int f2e_cli_streq(const char *a, const char *b) {
  return strcmp(a, b) == 0;
}

static void f2e_cli_stderr_locked(const char *format, ...) {
#if !defined(_WIN32)
  flockfile(stderr);
#endif
  va_list args;
  va_start(args, format);
  vfprintf(stderr, format, args);
  va_end(args);
  fflush(stderr);
#if !defined(_WIN32)
  funlockfile(stderr);
#endif
}

static int f2e_cli_stdout_write_locked(const char *value) {
  if (!value) {
    return 0;
  }
#if !defined(_WIN32)
  flockfile(stdout);
#endif
  int ok = fputs(value, stdout) != EOF;
  if (fflush(stdout) == EOF) {
    ok = 0;
  }
#if !defined(_WIN32)
  funlockfile(stdout);
#endif
  return ok;
}

static int f2e_cli_stdout_line_locked(const char *value) {
#if !defined(_WIN32)
  flockfile(stdout);
#endif
  int ok = fputs(value ? value : "", stdout) != EOF;
  if (ok && fputc('\n', stdout) == EOF) {
    ok = 0;
  }
  if (fflush(stdout) == EOF) {
    ok = 0;
  }
#if !defined(_WIN32)
  funlockfile(stdout);
#endif
  return ok;
}

static char *f2e_cli_strdup(const char *value) {
  size_t len = value ? strlen(value) : 0;
  char *copy = (char *)malloc(len + 1);
  if (!copy) {
    return NULL;
  }
  if (len > 0 && value) {
    memcpy(copy, value, len);
  }
  copy[len] = '\0';
  return copy;
}

static char *f2e_cli_join_path(const char *dir, const char *name) {
  if (!dir || !name) {
    return NULL;
  }
  size_t dir_len = strlen(dir);
  size_t name_len = strlen(name);
  size_t separator = dir_len > 0 && dir[dir_len - 1] != '/' && dir[dir_len - 1] != '\\' ? 1 : 0;
  if (dir_len > SIZE_MAX - separator - name_len - 1) {
    return NULL;
  }
  char *path = (char *)malloc(dir_len + separator + name_len + 1);
  if (!path) {
    return NULL;
  }
  memcpy(path, dir, dir_len);
  size_t offset = dir_len;
  if (separator) {
    path[offset++] = '/';
  }
  memcpy(path + offset, name, name_len);
  path[offset + name_len] = '\0';
  return path;
}

static char *f2e_cli_shell_quote(const char *value) {
  size_t extra = 2;
  for (const char *cursor = value ? value : ""; *cursor; cursor++) {
    extra += *cursor == '\'' ? 4 : 1;
  }
  char *quoted = (char *)malloc(extra + 1);
  if (!quoted) {
    return NULL;
  }
  size_t offset = 0;
  quoted[offset++] = '\'';
  for (const char *cursor = value ? value : ""; *cursor; cursor++) {
    if (*cursor == '\'') {
      memcpy(quoted + offset, "'\\''", 4);
      offset += 4;
    } else {
      quoted[offset++] = *cursor;
    }
  }
  quoted[offset++] = '\'';
  quoted[offset] = '\0';
  return quoted;
}

static int f2e_cli_mkdir_p(const char *path) {
  if (!path || path[0] == '\0') {
    return 0;
  }
  char tmp[PATH_MAX];
  if (strlen(path) >= sizeof(tmp)) {
    return 0;
  }
  strcpy(tmp, path);

  for (char *cursor = tmp + 1; *cursor; cursor++) {
    if (*cursor == '/' || *cursor == '\\') {
      char saved = *cursor;
      *cursor = '\0';
      if (tmp[0] != '\0' && F2E_MKDIR(tmp) != 0 && errno != EEXIST) {
        return 0;
      }
      *cursor = saved;
    }
  }
  return F2E_MKDIR(tmp) == 0 || errno == EEXIST;
}

static int f2e_cli_write_file(const char *path, const char *contents) {
  FILE *file = fopen(path, "w");
  if (!file) {
    return 0;
  }
  int ok = fputs(contents ? contents : "", file) >= 0;
  if (fclose(file) != 0) {
    ok = 0;
  }
  return ok;
}

static int f2e_cli_file_contains(const char *path, const char *needle) {
  FILE *file = fopen(path, "r");
  if (!file) {
    return 0;
  }
  char line[4096];
  int found = 0;
  while (fgets(line, sizeof(line), file)) {
    if (strstr(line, needle)) {
      found = 1;
      break;
    }
  }
  fclose(file);
  return found;
}

static int f2e_cli_append_once(const char *path, const char *marker, const char *block) {
  if (f2e_cli_file_contains(path, marker)) {
    return 1;
  }
  FILE *file = fopen(path, "a");
  if (!file) {
    return 0;
  }
  int ok = fputs(block, file) >= 0;
  if (fclose(file) != 0) {
    ok = 0;
  }
  return ok;
}

static char *f2e_cli_default_completion_dir(const char *shell) {
  const char *specific = NULL;
  if (f2e_cli_streq(shell, "bash")) {
    specific = getenv("F2E_BASH_COMPLETION_DIR");
  } else if (f2e_cli_streq(shell, "zsh")) {
    specific = getenv("F2E_ZSH_COMPLETION_DIR");
  }
  if (specific && specific[0] != '\0') {
    return f2e_cli_strdup(specific);
  }

  const char *common = getenv("F2E_COMPLETION_DIR");
  if (common && common[0] != '\0') {
    return f2e_cli_strdup(common);
  }

  if (f2e_cli_streq(shell, "bash")) {
    const char *xdg = getenv("XDG_DATA_HOME");
    if (xdg && xdg[0] != '\0') {
      return f2e_cli_join_path(xdg, "bash-completion/completions");
    }
    const char *home = getenv("HOME");
    if (!home || home[0] == '\0') {
      return NULL;
    }
    return f2e_cli_join_path(home, ".local/share/bash-completion/completions");
  }

  if (f2e_cli_streq(shell, "zsh")) {
    const char *zdotdir = getenv("ZDOTDIR");
    const char *base = zdotdir && zdotdir[0] != '\0' ? zdotdir : getenv("HOME");
    if (!base || base[0] == '\0') {
      return NULL;
    }
    return f2e_cli_join_path(base, ".zfunc");
  }

  return NULL;
}

static char *f2e_cli_rc_path(const char *shell) {
  const char *override = NULL;
  if (f2e_cli_streq(shell, "bash")) {
    override = getenv("F2E_BASHRC");
  } else if (f2e_cli_streq(shell, "zsh")) {
    override = getenv("F2E_ZSHRC");
  }
  if (override && override[0] != '\0') {
    return f2e_cli_strdup(override);
  }

  if (f2e_cli_streq(shell, "bash")) {
    const char *home = getenv("HOME");
    return home && home[0] != '\0' ? f2e_cli_join_path(home, ".bashrc") : NULL;
  }
  if (f2e_cli_streq(shell, "zsh")) {
    const char *zdotdir = getenv("ZDOTDIR");
    const char *base = zdotdir && zdotdir[0] != '\0' ? zdotdir : getenv("HOME");
    return base && base[0] != '\0' ? f2e_cli_join_path(base, ".zshrc") : NULL;
  }
  return NULL;
}

static int f2e_cli_command_basename(const char *command, const char **base_out, size_t *len_out) {
  int used_default = !command || command[0] == '\0';
  const char *path = used_default ? "flags2env" : command;
  size_t len = strlen(path);
  while (len > 0 && (path[len - 1] == '/' || path[len - 1] == '\\')) {
    len--;
  }
  if (len == 0) {
    if (!used_default) {
      return 0;
    }
    path = "flags2env";
    len = strlen(path);
  }

  size_t start = 0;
  for (size_t i = len; i > 0; i--) {
    if (path[i - 1] == '/' || path[i - 1] == '\\') {
      start = i;
      break;
    }
  }

  if (!base_out || !len_out || len <= start) {
    return 0;
  }
  *base_out = path + start;
  *len_out = len - start;
  return 1;
}

static char *f2e_cli_completion_file_name(const char *shell, const char *command) {
  const char *base = NULL;
  size_t len = 0;
  if (!f2e_cli_command_basename(command, &base, &len)) {
    return NULL;
  }

  size_t prefix = f2e_cli_streq(shell, "zsh") ? 1 : 0;
  if (len > SIZE_MAX - prefix - 1) {
    return NULL;
  }
  char *name = (char *)malloc(prefix + len + 1);
  if (!name) {
    return NULL;
  }
  size_t offset = 0;
  if (prefix) {
    name[offset++] = '_';
  }
  for (size_t i = 0; i < len; i++) {
    unsigned char ch = (unsigned char)base[i];
    name[offset++] = isalnum(ch) || ch == '.' || ch == '_' || ch == '-'
                         ? (char)ch
                         : '_';
  }
  name[offset] = '\0';
  return name;
}

static int f2e_cli_update_shell_rc(const char *shell, const char *command, const char *completion_path, const char *completion_dir) {
  char *rc_path = f2e_cli_rc_path(shell);
  if (!rc_path) {
    return 0;
  }

  char *command_label = f2e_cli_completion_file_name("bash", command);
  if (!command_label) {
    free(rc_path);
    return 0;
  }

  char marker[256];
  int marker_len = snprintf(marker, sizeof(marker), "# flags2env completion: %s %s", shell, command_label);
  if (marker_len <= 0 || (size_t)marker_len >= sizeof(marker)) {
    free(rc_path);
    free(command_label);
    return 0;
  }

  char *quoted_path = f2e_cli_shell_quote(completion_path);
  char *quoted_dir = f2e_cli_shell_quote(completion_dir);
  if (!quoted_path || !quoted_dir) {
    free(rc_path);
    free(command_label);
    free(quoted_path);
    free(quoted_dir);
    return 0;
  }

  char block[PATH_MAX * 4];
  int block_len = 0;
  if (f2e_cli_streq(shell, "bash")) {
    block_len = snprintf(block, sizeof(block), "\n%s\n[ -f %s ] && . %s\n", marker, quoted_path, quoted_path);
  } else {
    block_len = snprintf(block, sizeof(block),
                         "\n%s\nif [ -d %s ]; then\n  fpath=(%s $fpath)\n  autoload -Uz compinit\n  compinit\nfi\n",
                         marker,
                         quoted_dir,
                         quoted_dir);
  }
  if (block_len <= 0 || (size_t)block_len >= sizeof(block)) {
    free(rc_path);
    free(command_label);
    free(quoted_path);
    free(quoted_dir);
    return 0;
  }

  int ok = f2e_cli_append_once(rc_path, marker, block);
  free(rc_path);
  free(command_label);
  free(quoted_path);
  free(quoted_dir);
  return ok;
}

static int f2e_cli_print_owned(char *value, const char *fallback) {
  if (!value) {
    f2e_cli_stdout_line_locked(fallback);
    return 1;
  }
  int ok = f2e_cli_stdout_line_locked(value);
  f2e_free(value);
  return ok ? 0 : 1;
}

static const char *f2e_cli_help_command_name(int argc, const char *const argv[]) {
  if (argc >= 2 && argv[1] && argv[1][0] != '-' &&
      !f2e_cli_streq(argv[1], "audit") &&
      !f2e_cli_streq(argv[1], "completion") &&
      !f2e_cli_streq(argv[1], "completions") &&
      !f2e_cli_streq(argv[1], "autocomplete") &&
      !f2e_cli_streq(argv[1], "env-audit") &&
      !f2e_cli_streq(argv[1], "audit-env") &&
      !f2e_cli_streq(argv[1], "env-check") &&
      !f2e_cli_streq(argv[1], "install-completion") &&
      !f2e_cli_streq(argv[1], "install-autocomplete")) {
    return argv[1];
  }
  return argc >= 1 && argv[0] ? argv[0] : "flags2env";
}

static int f2e_cli_run_audit(const char *config_path) {
  char *report = config_path ? f2e_audit_config_from_file(config_path) : f2e_audit_config();
  int status = config_path ? f2e_audit_config_status_from_file(config_path) : f2e_audit_config_status();
  if (!report) {
    f2e_cli_stdout_line_locked("{\"ok\":false,\"errors\":[\"audit failed\"]}");
    return 1;
  }
  int ok = f2e_cli_stdout_line_locked(report);
  f2e_free(report);
  return ok ? status : 1;
}

static int f2e_cli_run_env_audit(const char *config_path, const char *env_path) {
  char *report = config_path ? f2e_audit_env_file_from_file(config_path, env_path) : f2e_audit_env_file();
  int status = config_path ? f2e_audit_env_file_status_from_file(config_path, env_path) : f2e_audit_env_file_status();
  if (!report) {
    f2e_cli_stdout_line_locked("{\"ok\":false,\"errors\":[\"env audit failed\"]}");
    return 1;
  }
  int ok = f2e_cli_stdout_line_locked(report);
  f2e_free(report);
  return ok ? status : 1;
}

static int f2e_cli_run_completion(const char *shell, const char *command, const char *config_path) {
  char *script = config_path ? f2e_completion_script_from_file(config_path, shell, command)
                             : f2e_completion_script(shell, command);
  if (!script) {
    f2e_cli_stderr_locked("flags2env: could not generate %s completion for %s\n",
                          shell ? shell : "",
                          command ? command : "");
    return 1;
  }
  int ok = f2e_cli_stdout_write_locked(script);
  f2e_free(script);
  return ok ? 0 : 1;
}

static int f2e_cli_install_completion(const char *shell, const char *command, const char *config_path) {
  if (!f2e_cli_streq(shell, "bash") && !f2e_cli_streq(shell, "zsh")) {
    f2e_cli_stderr_locked("flags2env: unsupported completion shell: %s\n", shell ? shell : "");
    return 1;
  }

  char *script = config_path ? f2e_completion_script_from_file(config_path, shell, command)
                             : f2e_completion_script(shell, command);
  if (!script) {
    f2e_cli_stderr_locked("flags2env: could not generate %s completion for %s\n", shell, command);
    return 1;
  }

  char *dir = f2e_cli_default_completion_dir(shell);
  char *file_name = f2e_cli_completion_file_name(shell, command);
  char *path = dir && file_name ? f2e_cli_join_path(dir, file_name) : NULL;
  if (!dir || !file_name || !path || !f2e_cli_mkdir_p(dir) || !f2e_cli_write_file(path, script) ||
      !f2e_cli_update_shell_rc(shell, command, path, dir)) {
    f2e_cli_stderr_locked("flags2env: could not install %s completion for %s\n", shell, command);
    free(script);
    free(dir);
    free(file_name);
    free(path);
    return 1;
  }

  char installed[PATH_MAX * 2];
  int installed_len = snprintf(installed, sizeof(installed),
                               "Installed %s completion for %s to %s",
                               shell,
                               command,
                               path);
  int printed = installed_len > 0 && (size_t)installed_len < sizeof(installed)
                    ? f2e_cli_stdout_line_locked(installed)
                    : 0;
  free(script);
  free(dir);
  free(file_name);
  free(path);
  return printed ? 0 : 1;
}

int main(int argc, const char *const argv[]) {
  if (f2e_is_help_requested(argc, argv)) {
    const char *command = f2e_cli_help_command_name(argc, argv);
    if (f2e_print_table(command, 0) != 0) {
      f2e_cli_stderr_locked("flags2env: could not generate help menu\n");
      return 1;
    }
    return 0;
  }

  if (argc >= 2 && (strcmp(argv[1], "audit") == 0 || strcmp(argv[1], "--audit") == 0)) {
    if (argc >= 3 && (f2e_cli_streq(argv[2], "env") || f2e_cli_streq(argv[2], "--env"))) {
      return f2e_cli_run_env_audit(argc >= 4 ? argv[3] : NULL, argc >= 5 ? argv[4] : NULL);
    }
    if (argc >= 3 && f2e_cli_streq(argv[2], "config")) {
      return f2e_cli_run_audit(argc >= 4 ? argv[3] : NULL);
    }
    return f2e_cli_run_audit(argc >= 3 ? argv[2] : NULL);
  }

  if (argc >= 2 && (f2e_cli_streq(argv[1], "env-audit") ||
                    f2e_cli_streq(argv[1], "audit-env") ||
                    f2e_cli_streq(argv[1], "env-check"))) {
    return f2e_cli_run_env_audit(argc >= 3 ? argv[2] : NULL, argc >= 4 ? argv[3] : NULL);
  }

  if (argc >= 2 && (f2e_cli_streq(argv[1], "completion") ||
                    f2e_cli_streq(argv[1], "completions") ||
                    f2e_cli_streq(argv[1], "autocomplete"))) {
    if (argc >= 3 && f2e_cli_streq(argv[2], "install")) {
      if (argc < 5) {
        f2e_cli_stderr_locked("%s", "usage: flags2env completion install <bash|zsh> <command> [config]\n");
        return 2;
      }
      return f2e_cli_install_completion(argv[3], argv[4], argc >= 6 ? argv[5] : NULL);
    }
    if (argc < 4) {
      f2e_cli_stderr_locked("%s", "usage: flags2env completion <bash|zsh> <command> [config]\n");
      return 2;
    }
    return f2e_cli_run_completion(argv[2], argv[3], argc >= 5 ? argv[4] : NULL);
  }

  if (argc >= 2 && (f2e_cli_streq(argv[1], "install-completion") ||
                    f2e_cli_streq(argv[1], "install-autocomplete"))) {
    if (argc < 4) {
      f2e_cli_stderr_locked("%s", "usage: flags2env install-completion <bash|zsh> <command> [config]\n");
      return 2;
    }
    return f2e_cli_install_completion(argv[2], argv[3], argc >= 5 ? argv[4] : NULL);
  }

  char *json = f2e_parse(argc, argv);
  return f2e_cli_print_owned(json, "{}");
}
