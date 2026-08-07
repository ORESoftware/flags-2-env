/*
 * Library-level checks for ./.env loading.
 *
 * tests/run.sh covers the resolved map through the CLI. This exercises what
 * the CLI cannot reach: the structured parse channels, the merge identity a
 * caller relies on when it combines them by hand, command scoping, and repeat
 * stability. Run it under leaks(1) or valgrind for allocation coverage.
 */

#if defined(__linux__) && !defined(_POSIX_C_SOURCE)
#define _POSIX_C_SOURCE 200809L
#endif

#include "parser.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int failures = 0;
static int checks = 0;

static void check(int condition, const char *label, const char *context) {
  checks++;
  if (!condition) {
    failures++;
    fprintf(stderr, "dotenv-api: FAIL %s\n  in: %s\n", label, context ? context : "");
  }
}

static void check_contains(const char *haystack, const char *needle, const char *label) {
  check(haystack && strstr(haystack, needle) != NULL, label, haystack);
}

static void check_absent(const char *haystack, const char *needle, const char *label) {
  check(haystack && strstr(haystack, needle) == NULL, label, haystack);
}

static int write_file(const char *path, const char *contents) {
  FILE *file = fopen(path, "wb");
  if (!file) {
    return 0;
  }
  int ok = fputs(contents, file) >= 0;
  return fclose(file) == 0 && ok;
}

static const char *const CONFIG =
    "[flags.host]\n"
    "env = \"API_HOST\"\n"
    "aliases = [\"host\"]\n"
    "type = \"string\"\n"
    "\n"
    "[flags.token]\n"
    "env = \"API_TOKEN\"\n"
    "aliases = [\"token\"]\n"
    "type = \"string\"\n"
    "dotenv_override = true\n"
    "\n"
    "[flags.port]\n"
    "env = \"API_PORT\"\n"
    "aliases = [\"port\"]\n"
    "type = \"integer\"\n"
    "default = 3000\n"
    "\n"
    "[commands.deploy]\n"
    "env = \"API_CMD_DEPLOY\"\n"
    "\n"
    "[commands.deploy.flags.region]\n"
    "env = \"API_REGION\"\n"
    "aliases = [\"region\"]\n"
    "type = \"string\"\n";

static const char *const DOTENV =
    "API_HOST=from-dotenv\n"
    "API_TOKEN=from-dotenv\n"
    "API_REGION=from-dotenv\n"
    "API_CMD_DEPLOY=true\n"
    "FLAGS2ENV_COMMAND=forged\n";

int main(void) {
  char template[] = "/tmp/f2e-dotenv-api.XXXXXX";
  const char *dir = mkdtemp(template);
  if (!dir || chdir(dir) != 0) {
    fprintf(stderr, "dotenv-api: could not create a working directory\n");
    return 1;
  }
  if (!write_file(".cli-flags.toml", CONFIG) || !write_file(".env", DOTENV)) {
    fprintf(stderr, "dotenv-api: could not write fixtures\n");
    return 1;
  }

  /* the environment this process hands to the parser */
  unsetenv("API_HOST");
  unsetenv("API_PORT");
  unsetenv("API_REGION");
  unsetenv("API_CMD_DEPLOY");
  unsetenv("FLAGS2ENV_COMMAND");
  unsetenv("FLAGS2ENV_DOTENV");
  setenv("API_TOKEN", "from-live", 1);

  const char *argv_plain[] = {"app"};
  const char *argv_deploy[] = {"app", "deploy"};
  const char *argv_flag[] = {"app", "--host", "from-flag"};

  /* resolved map: .env fills what neither argv nor the environment set */
  char *flags = f2e_parse(1, argv_plain);
  check_contains(flags, "\"API_HOST\":\"from-dotenv\"", "host comes from .env");
  check_contains(flags, "\"API_PORT\":\"3000\"", "port falls back to its default");
  check_contains(flags, "\"FLAGS2ENV_COMMAND\":\"\"", "no command selected");
  /* API_TOKEN declares dotenv_override, so the file outranks the live value */
  check_contains(flags, "\"API_TOKEN\":\"from-dotenv\"", "dotenv_override beats the live env");
  check_absent(flags, "forged", ".env cannot forge the command path");
  check_absent(flags, "API_REGION", "a scoped flag stays out until its command runs");
  f2e_free(flags);

  /* argv still outranks an overriding .env */
  char *overridden = f2e_parse(3, argv_flag);
  check_contains(overridden, "\"API_HOST\":\"from-flag\"", "argv beats .env");
  f2e_free(overridden);

  /* a scoped flag takes its .env value only while its command is selected */
  char *deployed = f2e_parse(2, argv_deploy);
  check_contains(deployed, "\"API_REGION\":\"from-dotenv\"", "scoped flag reads .env when active");
  check_contains(deployed, "\"FLAGS2ENV_COMMAND\":\"deploy\"", "command path comes from argv");
  f2e_free(deployed);

  /* structured channels */
  char *structured = f2e_parse_structured(1, argv_plain);
  check(structured != NULL, "structured parse returns a report", NULL);
  if (structured) {
    check_contains(structured, "\"dotenv\":{", "dotenv channel is present");
    check_contains(structured, "\"dotenvOverrides\":{", "dotenvOverrides channel is present");
    /* API_HOST loses to the environment, so it belongs under it */
    check_contains(structured, "\"API_HOST\":\"from-dotenv\"", "host appears in a dotenv channel");
    /* the split is what makes per-flag override survive a flat merge: the
       overriding key must be in dotenvOverrides, not dotenv */
    const char *below = strstr(structured, "\"dotenv\":{");
    const char *above = strstr(structured, "\"dotenvOverrides\":{");
    check(below && above && below < above, "channels appear in merge order", structured);
    if (below && above) {
      size_t below_len = (size_t)(above - below);
      char *below_copy = (char *)malloc(below_len + 1);
      if (below_copy) {
        memcpy(below_copy, below, below_len);
        below_copy[below_len] = '\0';
        check(strstr(below_copy, "API_TOKEN") == NULL,
              "an overriding key is not in the below-env channel", below_copy);
        check(strstr(below_copy, "API_HOST") != NULL,
              "a normal key is in the below-env channel", below_copy);
        free(below_copy);
      }
      check(strstr(above, "API_TOKEN") != NULL,
            "an overriding key is in the above-env channel", above);
    }
    /* providedFlags carries argv values and command markers only, never a
       value the file or the environment supplied */
    const char *provided = strstr(structured, "\"providedFlags\":{");
    const char *provided_end = provided ? strchr(provided, '}') : NULL;
    if (provided && provided_end) {
      size_t provided_len = (size_t)(provided_end - provided);
      char *provided_copy = (char *)malloc(provided_len + 1);
      if (provided_copy) {
        memcpy(provided_copy, provided, provided_len);
        provided_copy[provided_len] = '\0';
        check(strstr(provided_copy, "from-dotenv") == NULL && strstr(provided_copy, "from-live") == NULL,
              "providedFlags stays argv-only", provided_copy);
        free(provided_copy);
      }
    }
    check_absent(structured, "forged", ".env cannot forge structured channels");
    f2e_free(structured);
  }

  /* repeat parses are stable and independent */
  char *first = f2e_parse(1, argv_plain);
  char *second = f2e_parse(1, argv_plain);
  check(first && second && strcmp(first, second) == 0, "repeat parses agree", first);
  f2e_free(first);
  f2e_free(second);

  /* [env] load = false wins over an ambient FLAGS2ENV_DOTENV=1 */
  {
    char disabled_config[4096];
    int written = snprintf(disabled_config, sizeof(disabled_config), "[env]\nload = false\n\n%s", CONFIG);
    check(written > 0 && (size_t)written < sizeof(disabled_config), "built the load=false config", NULL);
    if (written > 0 && (size_t)written < sizeof(disabled_config) &&
        write_file(".cli-flags.toml", disabled_config)) {
      setenv("FLAGS2ENV_DOTENV", "1", 1);
      char *off = f2e_parse(1, argv_plain);
      check_absent(off, "from-dotenv", "load = false ignores .env despite FLAGS2ENV_DOTENV=1");
      check_contains(off, "\"API_TOKEN\":\"from-live\"", "the live value still applies");
      f2e_free(off);
      unsetenv("FLAGS2ENV_DOTENV");
    }
    /* and the file is read again once loading is re-enabled */
    if (write_file(".cli-flags.toml", CONFIG)) {
      char *on = f2e_parse(1, argv_plain);
      check_contains(on, "from-dotenv", "loading resumes when the config allows it");
      f2e_free(on);
    }
  }

  /* [order-of-preference] re-ranks the sources per key, including ranking
     argv last so a checked-in value cannot be overridden from the CLI */
  {
    static const char *const ORDER_CONFIG =
        "[order-of-preference]\n"
        "API_HOST = (env_file, env_shell, flags)\n"
        "API_TOKEN = (env_shell, flags)\n"
        "API_PORT = [env_file, flags]\n"
        "\n"
        "[flags.host]\n"
        "env = \"API_HOST\"\n"
        "aliases = [\"host\"]\n"
        "type = \"string\"\n"
        "\n"
        "[flags.token]\n"
        "env = \"API_TOKEN\"\n"
        "aliases = [\"token\"]\n"
        "type = \"string\"\n"
        "\n"
        "[flags.port]\n"
        "env = \"API_PORT\"\n"
        "aliases = [\"port\"]\n"
        "type = \"integer\"\n"
        "default = 3000\n";
    static const char *const ORDER_DOTENV =
        "API_HOST=from-dotenv\n"
        "API_TOKEN=from-dotenv\n"
        "API_PORT=8080\n";

    if (write_file(".cli-flags.toml", ORDER_CONFIG) && write_file(".env", ORDER_DOTENV)) {
      setenv("API_HOST", "from-live", 1);
      setenv("API_TOKEN", "from-live", 1);
      setenv("API_PORT", "7777", 1);

      const char *argv_all[] = {"app", "--host", "from-flag", "--token", "from-flag", "--port", "9999"};
      char *ranked = f2e_parse(7, argv_all);
      /* env_file first, so neither the shell nor argv displaces it */
      check_contains(ranked, "\"API_HOST\":\"from-dotenv\"", "env_file ranked first beats argv");
      /* env_shell > flags > env_file */
      check_contains(ranked, "\"API_TOKEN\":\"from-live\"", "env_shell ranked first beats argv");
      /* env_file > flags, with env_shell appended last */
      check_contains(ranked, "\"API_PORT\":\"8080\"", "a two-entry list ranks env_file over argv");
      f2e_free(ranked);

      /* with the file gone, each key falls to the next rank in its own list */
      unlink(".env");
      char *fallen = f2e_parse(7, argv_all);
      check_contains(fallen, "\"API_HOST\":\"from-live\"", "env_file absent falls to env_shell");
      check_contains(fallen, "\"API_TOKEN\":\"from-live\"", "env_shell still wins");
      /* API_PORT completed to env_file > flags > env_shell, so argv wins here */
      check_contains(fallen, "\"API_PORT\":\"9999\"", "completion puts the omitted source last");
      f2e_free(fallen);

      char *report = f2e_parse_structured(7, argv_all);
      if (report) {
        check_contains(report, "\"sourceOrder\":{", "sourceOrder channel is present");
        check_contains(report, "[\"env_file\",\"env_shell\",\"flags\"]", "a full list is reported verbatim");
        check_contains(report, "[\"env_shell\",\"flags\",\"env_file\"]", "a partial list is reported completed");
        f2e_free(report);
      }

      unsetenv("API_HOST");
      unsetenv("API_TOKEN");
      unsetenv("API_PORT");
    }
  }

  /* a key with no entry keeps the default order */
  {
    static const char *const MIXED_CONFIG =
        "[order-of-preference]\n"
        "API_HOST = (env_file, flags)\n"
        "\n"
        "[flags.host]\n"
        "env = \"API_HOST\"\n"
        "aliases = [\"host\"]\n"
        "type = \"string\"\n"
        "\n"
        "[flags.token]\n"
        "env = \"API_TOKEN\"\n"
        "aliases = [\"token\"]\n"
        "type = \"string\"\n";
    if (write_file(".cli-flags.toml", MIXED_CONFIG) &&
        write_file(".env", "API_HOST=from-dotenv\nAPI_TOKEN=from-dotenv\n")) {
      const char *argv_both[] = {"app", "--host", "from-flag", "--token", "from-flag"};
      char *mixed = f2e_parse(5, argv_both);
      check_contains(mixed, "\"API_HOST\":\"from-dotenv\"", "listed key uses its order");
      check_contains(mixed, "\"API_TOKEN\":\"from-flag\"", "unlisted key keeps the default order");
      f2e_free(mixed);

      char *mixed_report = f2e_parse_structured(5, argv_both);
      if (mixed_report) {
        check_absent(mixed_report, "\"API_TOKEN\":[", "sourceOrder omits default-order keys");
        f2e_free(mixed_report);
      }
    }
  }

  unlink(".env");
  unlink(".cli-flags.toml");
  if (chdir("/") == 0) {
    rmdir(dir);
  }

  if (failures > 0) {
    fprintf(stderr, "dotenv-api: %d of %d checks failed\n", failures, checks);
    return 1;
  }
  printf("dotenv-api: %d checks passed\n", checks);
  return 0;
}
