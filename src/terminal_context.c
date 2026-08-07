#if !defined(_WIN32) && !defined(_POSIX_C_SOURCE)
#define _POSIX_C_SOURCE 200809L
#endif

#include "terminal_context.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <io.h>
#include <windows.h>
#define F2E_FILENO _fileno
#define F2E_ISATTY _isatty
#else
#include <sys/ioctl.h>
#include <unistd.h>
#define F2E_FILENO fileno
#define F2E_ISATTY isatty
#endif

struct f2e_terminal_snapshot {
  int stdin_tty;
  int stdout_tty;
  int stderr_tty;
  int ci;
  int dumb;
  int nested;
  int can_prompt;
  int color_stdout;
  int color_stderr;
  int unicode;
  int hyperlinks;
  unsigned int columns;
  const char *shell;
  const char *shell_source;
  const char *output_mode;
  const char *terminal;
};

static int f2e_ascii_equal_ci(const char *left, const char *right) {
  if (!left || !right) {
    return 0;
  }
  while (*left && *right) {
    if (tolower((unsigned char)*left) != tolower((unsigned char)*right)) {
      return 0;
    }
    left++;
    right++;
  }
  return *left == '\0' && *right == '\0';
}

static int f2e_ascii_contains_ci(const char *value, const char *needle) {
  if (!value || !needle || !*needle) {
    return 0;
  }
  size_t needle_len = strlen(needle);
  for (const char *cursor = value; *cursor; cursor++) {
    size_t index = 0;
    while (index < needle_len && cursor[index] &&
           tolower((unsigned char)cursor[index]) ==
               tolower((unsigned char)needle[index])) {
      index++;
    }
    if (index == needle_len) {
      return 1;
    }
  }
  return 0;
}

static int f2e_env_present(const char *name) {
  return getenv(name) != NULL;
}

static int f2e_value_truthy(const char *value) {
  if (!value || !*value) {
    return 0;
  }
  return !(f2e_ascii_equal_ci(value, "0") ||
           f2e_ascii_equal_ci(value, "false") ||
           f2e_ascii_equal_ci(value, "no") ||
           f2e_ascii_equal_ci(value, "off") ||
           f2e_ascii_equal_ci(value, "never"));
}

static int f2e_forced_bool(const char *name, int detected) {
  const char *value = getenv(name);
  if (!value || !*value || f2e_ascii_equal_ci(value, "auto")) {
    return detected;
  }
  return f2e_value_truthy(value);
}

static const char *f2e_path_basename(const char *path) {
  const char *base = path ? path : "";
  for (const char *cursor = base; *cursor; cursor++) {
    if (*cursor == '/' || *cursor == '\\') {
      base = cursor + 1;
    }
  }
  return base;
}

static const char *f2e_classify_shell(const char *value) {
  const char *base = f2e_path_basename(value);
  if (f2e_ascii_equal_ci(base, "pwsh") ||
      f2e_ascii_equal_ci(base, "pwsh.exe") ||
      f2e_ascii_equal_ci(base, "powershell") ||
      f2e_ascii_equal_ci(base, "powershell.exe")) {
    return "powershell";
  }
  if (f2e_ascii_equal_ci(base, "nu") || f2e_ascii_equal_ci(base, "nu.exe") ||
      f2e_ascii_equal_ci(base, "nushell")) {
    return "nushell";
  }
  if (f2e_ascii_contains_ci(base, "fish")) {
    return "fish";
  }
  if (f2e_ascii_contains_ci(base, "zsh")) {
    return "zsh";
  }
  if (f2e_ascii_contains_ci(base, "bash")) {
    return "bash";
  }
  if (f2e_ascii_equal_ci(base, "cmd") || f2e_ascii_equal_ci(base, "cmd.exe")) {
    return "cmd";
  }
  if (f2e_ascii_equal_ci(base, "sh") || f2e_ascii_equal_ci(base, "sh.exe") ||
      f2e_ascii_contains_ci(base, "dash") ||
      f2e_ascii_contains_ci(base, "ksh") ||
      f2e_ascii_contains_ci(base, "ash")) {
    return "sh";
  }
  return "unknown";
}

static const char *f2e_detect_shell(const char **source_out) {
  const char *override = getenv("F2E_SHELL");
  if (override && *override) {
    *source_out = "override";
    return f2e_classify_shell(override);
  }

  const char *shell = getenv("SHELL");
  if (shell && *shell) {
    *source_out = "shell-env";
    return f2e_classify_shell(shell);
  }

  if (f2e_env_present("POWERSHELL_DISTRIBUTION_CHANNEL") ||
      f2e_env_present("PSModulePath")) {
    *source_out = "powershell-env";
    return "powershell";
  }

  const char *comspec = getenv("COMSPEC");
  if (comspec && *comspec) {
    *source_out = "comspec";
    return f2e_classify_shell(comspec);
  }

  const char *parent = getenv("F2E_CONTEXT_SHELL");
  if (parent && *parent) {
    *source_out = "parent-context";
    return f2e_classify_shell(parent);
  }

  *source_out = "unknown";
  return "unknown";
}

const char *f2e_terminal_shell_family(void) {
  const char *source = NULL;
  return f2e_detect_shell(&source);
}

static int f2e_detect_ci(void) {
  const char *ci = getenv("CI");
  if (ci && f2e_value_truthy(ci)) {
    return 1;
  }
  const char *markers[] = {
      "GITHUB_ACTIONS", "GITLAB_CI", "BUILDKITE", "CIRCLECI",
      "TF_BUILD",       "JENKINS_URL", "TEAMCITY_VERSION", "BUILD_BUILDID"};
  size_t count = sizeof(markers) / sizeof(markers[0]);
  for (size_t index = 0; index < count; index++) {
    if (f2e_env_present(markers[index])) {
      return 1;
    }
  }
  return 0;
}

static unsigned int f2e_parse_columns(const char *value) {
  if (!value || !*value) {
    return 0;
  }
  char *end = NULL;
  unsigned long parsed = strtoul(value, &end, 10);
  if (!end || *end != '\0' || parsed < 20 || parsed > 10000) {
    return 0;
  }
  return (unsigned int)parsed;
}

static unsigned int f2e_terminal_columns_for_fd(int fd) {
#if defined(_WIN32)
  HANDLE handle = INVALID_HANDLE_VALUE;
  if (fd == F2E_FILENO(stdout)) {
    handle = GetStdHandle(STD_OUTPUT_HANDLE);
  } else if (fd == F2E_FILENO(stderr)) {
    handle = GetStdHandle(STD_ERROR_HANDLE);
  }
  CONSOLE_SCREEN_BUFFER_INFO info;
  if (handle != INVALID_HANDLE_VALUE && GetConsoleScreenBufferInfo(handle, &info)) {
    SHORT width = (SHORT)(info.srWindow.Right - info.srWindow.Left + 1);
    return width > 0 ? (unsigned int)width : 0;
  }
  return 0;
#else
#if defined(TIOCGWINSZ)
  struct winsize size;
  memset(&size, 0, sizeof(size));
  if (ioctl(fd, TIOCGWINSZ, &size) == 0 && size.ws_col > 0) {
    return (unsigned int)size.ws_col;
  }
#endif
  return 0;
#endif
}

static int f2e_detect_unicode(void) {
  int detected = 0;
#if defined(_WIN32)
  detected = GetConsoleOutputCP() == CP_UTF8 || f2e_env_present("WT_SESSION");
#else
  const char *locale = getenv("LC_ALL");
  if (!locale || !*locale) {
    locale = getenv("LC_CTYPE");
  }
  if (!locale || !*locale) {
    locale = getenv("LANG");
  }
  detected = f2e_ascii_contains_ci(locale, "utf-8") ||
             f2e_ascii_contains_ci(locale, "utf8");
#endif
  return f2e_forced_bool("F2E_FORCE_UNICODE", detected);
}

static int f2e_color_enabled(int tty, int ci, int dumb) {
  const char *forced = getenv("F2E_FORCE_COLOR");
  if (forced && *forced && !f2e_ascii_equal_ci(forced, "auto")) {
    return f2e_value_truthy(forced);
  }
  if (f2e_env_present("NO_COLOR")) {
    return 0;
  }
  if (f2e_value_truthy(getenv("FORCE_COLOR")) ||
      f2e_value_truthy(getenv("CLICOLOR_FORCE"))) {
    return 1;
  }
  const char *clicolor = getenv("CLICOLOR");
  if (clicolor && (f2e_ascii_equal_ci(clicolor, "0") ||
                   f2e_ascii_equal_ci(clicolor, "false"))) {
    return 0;
  }
  return tty && !ci && !dumb;
}

static const char *f2e_detect_terminal_family(void) {
  const char *program = getenv("TERM_PROGRAM");
  if (program && *program) {
    if (f2e_ascii_contains_ci(program, "vscode")) {
      return "vscode";
    }
    if (f2e_ascii_contains_ci(program, "wezterm")) {
      return "wezterm";
    }
    if (f2e_ascii_contains_ci(program, "iterm")) {
      return "iterm";
    }
    if (f2e_ascii_contains_ci(program, "ghostty")) {
      return "ghostty";
    }
    if (f2e_ascii_contains_ci(program, "apple_terminal")) {
      return "apple-terminal";
    }
  }
  if (f2e_env_present("WT_SESSION")) {
    return "windows-terminal";
  }
  const char *term = getenv("TERM");
  if (f2e_env_present("TMUX") || f2e_ascii_contains_ci(term, "tmux")) {
    return "tmux";
  }
  if (f2e_ascii_contains_ci(term, "kitty")) {
    return "kitty";
  }
  if (f2e_ascii_contains_ci(term, "screen")) {
    return "screen";
  }
  return "unknown";
}

static int f2e_detect_hyperlinks(int stderr_tty, int ci, int dumb) {
  if (!stderr_tty || ci || dumb) {
    return 0;
  }
  if (f2e_env_present("WT_SESSION")) {
    return 1;
  }
  const char *program = getenv("TERM_PROGRAM");
  if (program && (f2e_ascii_contains_ci(program, "iterm") ||
                  f2e_ascii_contains_ci(program, "wezterm") ||
                  f2e_ascii_contains_ci(program, "vscode") ||
                  f2e_ascii_contains_ci(program, "ghostty"))) {
    return 1;
  }
  const char *term = getenv("TERM");
  if (f2e_ascii_contains_ci(term, "kitty")) {
    return 1;
  }
  return f2e_parse_columns(getenv("VTE_VERSION")) >= 5000;
}

static struct f2e_terminal_snapshot f2e_detect_snapshot(void) {
  struct f2e_terminal_snapshot snapshot;
  memset(&snapshot, 0, sizeof(snapshot));

  snapshot.stdin_tty = f2e_forced_bool(
      "F2E_FORCE_STDIN_TTY", F2E_ISATTY(F2E_FILENO(stdin)) != 0);
  snapshot.stdout_tty = f2e_forced_bool(
      "F2E_FORCE_STDOUT_TTY", F2E_ISATTY(F2E_FILENO(stdout)) != 0);
  snapshot.stderr_tty = f2e_forced_bool(
      "F2E_FORCE_STDERR_TTY", F2E_ISATTY(F2E_FILENO(stderr)) != 0);
  snapshot.ci = f2e_forced_bool("F2E_FORCE_CI", f2e_detect_ci());
  snapshot.dumb = f2e_ascii_equal_ci(getenv("TERM"), "dumb");
  snapshot.nested = f2e_env_present("F2E_CONTEXT_VERSION");
  snapshot.can_prompt = snapshot.stdin_tty && snapshot.stderr_tty &&
                        !snapshot.ci && !snapshot.dumb;
  snapshot.color_stdout =
      f2e_color_enabled(snapshot.stdout_tty, snapshot.ci, snapshot.dumb);
  snapshot.color_stderr =
      f2e_color_enabled(snapshot.stderr_tty, snapshot.ci, snapshot.dumb);
  snapshot.unicode = f2e_detect_unicode();
  snapshot.hyperlinks =
      f2e_detect_hyperlinks(snapshot.stderr_tty, snapshot.ci, snapshot.dumb);
  snapshot.columns = f2e_parse_columns(getenv("COLUMNS"));
  if (snapshot.columns == 0 && snapshot.stderr_tty) {
    snapshot.columns = f2e_terminal_columns_for_fd(F2E_FILENO(stderr));
  }
  if (snapshot.columns == 0 && snapshot.stdout_tty) {
    snapshot.columns = f2e_terminal_columns_for_fd(F2E_FILENO(stdout));
  }
  snapshot.shell = f2e_detect_shell(&snapshot.shell_source);
  snapshot.terminal = f2e_detect_terminal_family();
  if (snapshot.stdout_tty && !snapshot.ci && !snapshot.dumb) {
    snapshot.output_mode = "human";
  } else if (snapshot.stdout_tty || snapshot.stderr_tty) {
    snapshot.output_mode = "plain";
  } else {
    snapshot.output_mode = "machine";
  }
  return snapshot;
}

static const char *f2e_bool_text(int value) {
  return value ? "true" : "false";
}

char *f2e_terminal_context_json(void) {
  struct f2e_terminal_snapshot snapshot = f2e_detect_snapshot();
  char columns[32];
  if (snapshot.columns > 0) {
    snprintf(columns, sizeof(columns), "%u", snapshot.columns);
  } else {
    strcpy(columns, "null");
  }

  const char *format =
      "{\"version\":1,\"stdinTty\":%s,\"stdoutTty\":%s,\"stderrTty\":%s,"
      "\"interactive\":%s,\"canPrompt\":%s,\"ci\":%s,\"dumb\":%s,"
      "\"nested\":%s,\"outputMode\":\"%s\",\"shell\":\"%s\","
      "\"shellSource\":\"%s\","
      "\"terminal\":\"%s\",\"colorStdout\":%s,\"colorStderr\":%s,"
      "\"unicode\":%s,\"hyperlinks\":%s,\"columns\":%s}";
  size_t capacity = 1024;
  char *json = (char *)malloc(capacity);
  if (!json) {
    return NULL;
  }
  int written = snprintf(
      json, capacity, format,
      f2e_bool_text(snapshot.stdin_tty), f2e_bool_text(snapshot.stdout_tty),
      f2e_bool_text(snapshot.stderr_tty), f2e_bool_text(snapshot.can_prompt),
      f2e_bool_text(snapshot.can_prompt), f2e_bool_text(snapshot.ci),
      f2e_bool_text(snapshot.dumb), f2e_bool_text(snapshot.nested),
      snapshot.output_mode, snapshot.shell,
      snapshot.shell_source, snapshot.terminal,
      f2e_bool_text(snapshot.color_stdout),
      f2e_bool_text(snapshot.color_stderr), f2e_bool_text(snapshot.unicode),
      f2e_bool_text(snapshot.hyperlinks), columns);
  if (written < 0 || (size_t)written >= capacity) {
    free(json);
    return NULL;
  }
  return json;
}

char *f2e_terminal_context_env_json(void) {
  struct f2e_terminal_snapshot snapshot = f2e_detect_snapshot();
  char columns[32];
  snprintf(columns, sizeof(columns), "%u", snapshot.columns);
  const char *format =
      "{\"F2E_CONTEXT_VERSION\":\"1\","
      "\"F2E_CONTEXT_STDIN_TTY\":\"%s\","
      "\"F2E_CONTEXT_STDOUT_TTY\":\"%s\","
      "\"F2E_CONTEXT_STDERR_TTY\":\"%s\","
      "\"F2E_CONTEXT_INTERACTIVE\":\"%s\","
      "\"F2E_CONTEXT_CAN_PROMPT\":\"%s\","
      "\"F2E_CONTEXT_CI\":\"%s\","
      "\"F2E_CONTEXT_DUMB\":\"%s\","
      "\"F2E_CONTEXT_NESTED\":\"%s\","
      "\"F2E_CONTEXT_OUTPUT_MODE\":\"%s\","
      "\"F2E_CONTEXT_SHELL\":\"%s\","
      "\"F2E_CONTEXT_SHELL_SOURCE\":\"%s\","
      "\"F2E_CONTEXT_TERMINAL\":\"%s\","
      "\"F2E_CONTEXT_COLOR_STDOUT\":\"%s\","
      "\"F2E_CONTEXT_COLOR_STDERR\":\"%s\","
      "\"F2E_CONTEXT_UNICODE\":\"%s\","
      "\"F2E_CONTEXT_HYPERLINKS\":\"%s\","
      "\"F2E_CONTEXT_COLUMNS\":\"%s\"}";
  size_t capacity = 1536;
  char *json = (char *)malloc(capacity);
  if (!json) {
    return NULL;
  }
  int written = snprintf(
      json, capacity, format,
      f2e_bool_text(snapshot.stdin_tty), f2e_bool_text(snapshot.stdout_tty),
      f2e_bool_text(snapshot.stderr_tty), f2e_bool_text(snapshot.can_prompt),
      f2e_bool_text(snapshot.can_prompt), f2e_bool_text(snapshot.ci),
      f2e_bool_text(snapshot.dumb), f2e_bool_text(snapshot.nested),
      snapshot.output_mode, snapshot.shell,
      snapshot.shell_source, snapshot.terminal,
      f2e_bool_text(snapshot.color_stdout),
      f2e_bool_text(snapshot.color_stderr), f2e_bool_text(snapshot.unicode),
      f2e_bool_text(snapshot.hyperlinks), columns);
  if (written < 0 || (size_t)written >= capacity) {
    free(json);
    return NULL;
  }
  return json;
}

int f2e_terminal_stream_is_tty(const char *stream) {
  if (!stream) {
    return 0;
  }
  struct f2e_terminal_snapshot snapshot = f2e_detect_snapshot();
  if (f2e_ascii_equal_ci(stream, "stdin")) {
    return snapshot.stdin_tty;
  }
  if (f2e_ascii_equal_ci(stream, "stdout")) {
    return snapshot.stdout_tty;
  }
  if (f2e_ascii_equal_ci(stream, "stderr")) {
    return snapshot.stderr_tty;
  }
  return 0;
}

int f2e_terminal_can_prompt(void) {
  struct f2e_terminal_snapshot snapshot = f2e_detect_snapshot();
  return snapshot.can_prompt;
}
