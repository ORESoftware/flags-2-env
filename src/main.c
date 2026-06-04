#include "parser.h"

#include <ctype.h>
#include <errno.h>
#include <limits.h>
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

static char *f2e_cli_completion_file_name(const char *shell, const char *command) {
  const char *base = command && command[0] != '\0' ? command : "flags2env";
  const char *slash = strrchr(base, '/');
#if defined(_WIN32)
  const char *backslash = strrchr(base, '\\');
  if (!slash || (backslash && backslash > slash)) {
    slash = backslash;
  }
#endif
  if (slash && slash[1] != '\0') {
    base = slash + 1;
  }

  size_t prefix = f2e_cli_streq(shell, "zsh") ? 1 : 0;
  size_t len = strlen(base);
  char *name = (char *)malloc(prefix + len + 1);
  if (!name) {
    return NULL;
  }
  size_t offset = 0;
  if (prefix) {
    name[offset++] = '_';
  }
  for (const unsigned char *cursor = (const unsigned char *)base; *cursor; cursor++) {
    name[offset++] = isalnum(*cursor) || *cursor == '.' || *cursor == '_' || *cursor == '-'
                         ? (char)*cursor
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

  char marker[256];
  snprintf(marker, sizeof(marker), "# flags2env completion: %s %s", shell, command && command[0] != '\0' ? command : "flags2env");

  char *quoted_path = f2e_cli_shell_quote(completion_path);
  char *quoted_dir = f2e_cli_shell_quote(completion_dir);
  if (!quoted_path || !quoted_dir) {
    free(rc_path);
    free(quoted_path);
    free(quoted_dir);
    return 0;
  }

  char block[PATH_MAX * 4];
  if (f2e_cli_streq(shell, "bash")) {
    snprintf(block, sizeof(block), "\n%s\n[ -f %s ] && . %s\n", marker, quoted_path, quoted_path);
  } else {
    snprintf(block, sizeof(block),
             "\n%s\nif [ -d %s ]; then\n  fpath=(%s $fpath)\n  autoload -Uz compinit\n  compinit\nfi\n",
             marker,
             quoted_dir,
             quoted_dir);
  }

  int ok = f2e_cli_append_once(rc_path, marker, block);
  free(rc_path);
  free(quoted_path);
  free(quoted_dir);
  return ok;
}

static int f2e_cli_print_owned(char *value, const char *fallback) {
  if (!value) {
    fputs(fallback, stdout);
    fputc('\n', stdout);
    return 1;
  }
  fputs(value, stdout);
  fputc('\n', stdout);
  f2e_free(value);
  return 0;
}

static int f2e_cli_run_audit(const char *config_path) {
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

static int f2e_cli_run_env_audit(const char *config_path, const char *env_path) {
  char *report = config_path ? f2e_audit_env_file_from_file(config_path, env_path) : f2e_audit_env_file();
  int status = config_path ? f2e_audit_env_file_status_from_file(config_path, env_path) : f2e_audit_env_file_status();
  if (!report) {
    fputs("{\"ok\":false,\"errors\":[\"env audit failed\"]}\n", stdout);
    return 1;
  }
  fputs(report, stdout);
  fputc('\n', stdout);
  f2e_free(report);
  return status;
}

static int f2e_cli_run_completion(const char *shell, const char *command, const char *config_path) {
  char *script = config_path ? f2e_completion_script_from_file(config_path, shell, command)
                             : f2e_completion_script(shell, command);
  if (!script) {
    fprintf(stderr, "flags2env: could not generate %s completion for %s\n",
            shell ? shell : "",
            command ? command : "");
    return 1;
  }
  fputs(script, stdout);
  f2e_free(script);
  return 0;
}

static int f2e_cli_install_completion(const char *shell, const char *command, const char *config_path) {
  if (!f2e_cli_streq(shell, "bash") && !f2e_cli_streq(shell, "zsh")) {
    fprintf(stderr, "flags2env: unsupported completion shell: %s\n", shell ? shell : "");
    return 1;
  }

  char *script = config_path ? f2e_completion_script_from_file(config_path, shell, command)
                             : f2e_completion_script(shell, command);
  if (!script) {
    fprintf(stderr, "flags2env: could not generate %s completion for %s\n", shell, command);
    return 1;
  }

  char *dir = f2e_cli_default_completion_dir(shell);
  char *file_name = f2e_cli_completion_file_name(shell, command);
  char *path = dir && file_name ? f2e_cli_join_path(dir, file_name) : NULL;
  if (!dir || !file_name || !path || !f2e_cli_mkdir_p(dir) || !f2e_cli_write_file(path, script) ||
      !f2e_cli_update_shell_rc(shell, command, path, dir)) {
    fprintf(stderr, "flags2env: could not install %s completion for %s\n", shell, command);
    free(script);
    free(dir);
    free(file_name);
    free(path);
    return 1;
  }

  printf("Installed %s completion for %s to %s\n", shell, command, path);
  free(script);
  free(dir);
  free(file_name);
  free(path);
  return 0;
}

int main(int argc, const char *const argv[]) {
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
        fputs("usage: flags2env completion install <bash|zsh> <command> [config]\n", stderr);
        return 2;
      }
      return f2e_cli_install_completion(argv[3], argv[4], argc >= 6 ? argv[5] : NULL);
    }
    if (argc < 4) {
      fputs("usage: flags2env completion <bash|zsh> <command> [config]\n", stderr);
      return 2;
    }
    return f2e_cli_run_completion(argv[2], argv[3], argc >= 5 ? argv[4] : NULL);
  }

  if (argc >= 2 && (f2e_cli_streq(argv[1], "install-completion") ||
                    f2e_cli_streq(argv[1], "install-autocomplete"))) {
    if (argc < 4) {
      fputs("usage: flags2env install-completion <bash|zsh> <command> [config]\n", stderr);
      return 2;
    }
    return f2e_cli_install_completion(argv[2], argv[3], argc >= 5 ? argv[4] : NULL);
  }

  char *json = f2e_parse(argc, argv);
  return f2e_cli_print_owned(json, "{}");
}
