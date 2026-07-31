from __future__ import annotations

from pathlib import Path


def replace_exact(path: Path, old: str, new: str, *, count: int = 1) -> None:
    text = path.read_text(encoding="utf-8")
    actual = text.count(old)
    if actual != count:
        raise RuntimeError(f"{path}: expected {count} occurrence(s), found {actual}: {old[:120]!r}")
    path.write_text(text.replace(old, new, count), encoding="utf-8")


def append_once(path: Path, marker: str, block: str) -> None:
    text = path.read_text(encoding="utf-8")
    if marker in text:
        return
    if not text.endswith("\n"):
        text += "\n"
    path.write_text(text + "\n" + block.strip() + "\n", encoding="utf-8")


repo = Path(".")
parser_paths = []
for path in [repo / "src/parser.c", *sorted((repo / "clients").rglob("parser.c"))]:
    if not path.is_file():
        continue
    text = path.read_text(encoding="utf-8")
    if "f2e_completion_emit_scope_helpers" in text:
        parser_paths.append(path)

if not parser_paths:
    raise RuntimeError("no canonical or vendored parser.c files found")

signature_old = (
    "static int f2e_completion_emit_scope_helpers(const F2EConfig *config, "
    "F2EBuffer *script, const char *function_name) {"
)
signature_new = (
    "static int f2e_completion_emit_scope_helpers(const F2EConfig *config, "
    "F2EBuffer *script, const char *function_name, const char *bool_values) {"
)

helper_tail_old = r'''    for (size_t j = 0; j < command->alias_count; j++) {
      snprintf(pattern, sizeof(pattern), "%s|%s", parent_key, command->aliases[j]);
      if (!f2e_completion_emit_case_entry(script, pattern, child_key)) {
        return 0;
      }
    }
  }
  return f2e_buffer_append(script, "    *) printf '%s' '' ;;\n  esac\n}\n");
}'''
helper_tail_new = r'''    for (size_t j = 0; j < command->alias_count; j++) {
      snprintf(pattern, sizeof(pattern), "%s|%s", parent_key, command->aliases[j]);
      if (!f2e_completion_emit_case_entry(script, pattern, child_key)) {
        return 0;
      }
    }
  }
  if (!f2e_buffer_append(script, "    *) printf '%s' '' ;;\n  esac\n}\n") ||
      !f2e_buffer_append(script, function_name) ||
      !f2e_buffer_append(script, "_consumes_value() {\n"
                                 "  local opt value_opts bool_value_opts\n"
                                 "  value_opts=\"$(") ||
      !f2e_buffer_append(script, function_name) ||
      !f2e_buffer_append(script, "_value_opts \"$1\")\"\n"
                                 "  for opt in $value_opts; do\n"
                                 "    if [ \"$2\" = \"$opt\" ]; then\n"
                                 "      return 0\n"
                                 "    fi\n"
                                 "  done\n"
                                 "  bool_value_opts=\"$(") ||
      !f2e_buffer_append(script, function_name) ||
      !f2e_buffer_append(script, "_bool_value_opts \"$1\")\"\n"
                                 "  for opt in $bool_value_opts; do\n"
                                 "    if [ \"$2\" = \"$opt\" ]; then\n"
                                 "      case \" ") ||
      !f2e_buffer_append(script, bool_values ? bool_values : "") ||
      !f2e_buffer_append(script, " \" in\n"
                                 "        *\" $3 \"*) return 0 ;;\n"
                                 "      esac\n"
                                 "    fi\n"
                                 "  done\n"
                                 "  return 1\n"
                                 "}\n")) {
    return 0;
  }
  return 1;
}'''

bash_loop_old = r'''                                      "    if [ \"$w\" = \"--\" ]; then\n"
                                      "      return 0\n"
                                      "    fi\n"
                                      "    case \"$w\" in\n"'''
bash_loop_new = r'''                                      "    if [ \"$w\" = \"--\" ]; then\n"
                                      "      return 0\n"
                                      "    fi\n") &&
           f2e_buffer_append(&script, "    if ") &&
           f2e_buffer_append(&script, function_name) &&
           f2e_buffer_append(&script, "_consumes_value \"$scope\" \"${COMP_WORDS[i-1]}\" \"$w\"; then\n"
                                      "      continue\n"
                                      "    fi\n"
                                      "    case \"$w\" in\n"'''

zsh_loop_old = r'''                                      "    if [ \"$w\" = \"--\" ]; then\n"
                                      "      _files\n"
                                      "      return\n"
                                      "    fi\n"
                                      "    case \"$w\" in\n"'''
zsh_loop_new = r'''                                      "    if [ \"$w\" = \"--\" ]; then\n"
                                      "      _files\n"
                                      "      return\n"
                                      "    fi\n") &&
           f2e_buffer_append(&script, "    if ") &&
           f2e_buffer_append(&script, function_name) &&
           f2e_buffer_append(&script, "_consumes_value \"$scope\" \"${words[i-1]}\" \"$w\"; then\n"
                                      "      continue\n"
                                      "    fi\n"
                                      "    case \"$w\" in\n"'''

alias_audit_old = r'''      if (alias[0] == '\0' || alias[0] == '-' || !f2e_option_name_is_valid(alias)) {
        f2e_audit_add(audit, 1, "commands.%s alias \"%s\" contains unsafe characters", label, alias);
      }'''
alias_audit_new = r'''      if (alias[0] == '\0' || alias[0] == '-' || !f2e_option_name_is_valid(alias)) {
        f2e_audit_add(audit, 1, "commands.%s alias \"%s\" contains unsafe characters", label, alias);
      } else if (f2e_streq(alias, command->name)) {
        f2e_audit_add(audit, 1, "commands.%s alias \"%s\" duplicates its canonical name", label, alias);
      }'''

for path in parser_paths:
    replace_exact(path, signature_old, signature_new)
    replace_exact(path, helper_tail_old, helper_tail_new)
    replace_exact(
        path,
        "f2e_completion_emit_scope_helpers(config, &script, function_name) &&",
        "f2e_completion_emit_scope_helpers(config, &script, function_name, bool_values.data) &&",
        count=2,
    )
    replace_exact(path, bash_loop_old, bash_loop_new)
    replace_exact(path, zsh_loop_old, zsh_loop_new)
    replace_exact(path, alias_audit_old, alias_audit_new)

# Deep aliases at every command level.
deep = repo / "tests/subcommands-deep/.cli-flags.toml"
for old, new in [
    ("[commands.ws]\nhelp = \"Workspace operations.\"", "[commands.ws]\naliases = [\"workspace\"]\nhelp = \"Workspace operations.\""),
    ("[commands.ws.commands.remote]\nhelp = \"Manage workspace remotes.\"", "[commands.ws.commands.remote]\naliases = [\"remotes\"]\nhelp = \"Manage workspace remotes.\""),
    ("[commands.ws.commands.remote.commands.add]\nhelp = \"Add a workspace remote.\"", "[commands.ws.commands.remote.commands.add]\naliases = [\"create\"]\nhelp = \"Add a workspace remote.\""),
    ("[commands.ws.commands.remote.commands.add.commands.tag]\nhelp = \"Tag a newly added workspace remote.\"", "[commands.ws.commands.remote.commands.add.commands.tag]\naliases = [\"annotate\"]\nhelp = \"Tag a newly added workspace remote.\""),
]:
    replace_exact(deep, old, new)

# Completion regressions: canonical and alias scopes, plus command-looking values.
completion = repo / "tests/completion/run.bash"
completion_anchor = r'''reply="$(run_complete _flags2env_complete_tool tool ws remote add '' | tr '\n' ' ')"
expect_contains 'deep scope subcommands' "$reply" 'tag'
'''
completion_block = r'''reply="$(run_complete _flags2env_complete_tool tool ws remote add '' | tr '\n' ' ')"
expect_contains 'deep scope subcommands' "$reply" 'tag'
expect_contains 'deep scope subcommand aliases' "$reply" 'annotate'

# Every alias maps to the canonical nested scope.
reply="$(run_complete _flags2env_complete_tool tool workspace remotes create annotate '--' | tr '\n' ' ')"
expect_contains 'deep alias scope options' "$reply" '--name'
expect_contains 'deep alias scope options' "$reply" '--dry-run'

# A separated option value may equal either a command name or command alias;
# completion must consume it as a value rather than entering that command.
reply="$(run_complete _flags2env_complete_tool tool --label ws '' | tr '\n' ' ')"
expect_contains 'canonical command-looking value keeps root scope' "$reply" 'ws'
expect_contains 'canonical command-looking value keeps root aliases' "$reply" 'workspace'
expect_not_contains 'canonical command-looking value keeps root scope' "$reply" 'remote'
reply="$(run_complete _flags2env_complete_tool tool -l workspace '' | tr '\n' ' ')"
expect_contains 'alias-looking short-option value keeps root scope' "$reply" 'ws'
expect_not_contains 'alias-looking short-option value keeps root scope' "$reply" 'remotes'

# The same rule applies inside nested scopes.
reply="$(run_complete _flags2env_complete_tool tool ws remote add --url tag '--' | tr '\n' ' ')"
expect_contains 'nested canonical command-looking value stays in add' "$reply" '--url'
expect_not_contains 'nested canonical command-looking value stays in add' "$reply" '--name'
reply="$(run_complete _flags2env_complete_tool tool workspace remotes create -u annotate '--' | tr '\n' ' ')"
expect_contains 'nested alias-looking value stays in add' "$reply" '--url'
expect_not_contains 'nested alias-looking value stays in add' "$reply" '--name'

# Invalid separated bool values remain eligible as commands; only recognized
# bool values are consumed by completion.
reply="$(run_complete _flags2env_complete_tool tool --dry-run workspace '' | tr '\n' ' ')"
expect_contains 'invalid bool value remains a command alias' "$reply" 'remote'
expect_contains 'invalid bool value remains a command alias' "$reply" 'remotes'
'''
replace_exact(completion, completion_anchor, completion_block)

# Native parser API proves alias inputs produce canonical public paths.
api = repo / "tests/api_hardening.c"
replace_exact(
    api,
    '#define SUBCOMMANDS_CONFIG "tests/subcommands/.cli-flags.toml"\n',
    '#define SUBCOMMANDS_CONFIG "tests/subcommands/.cli-flags.toml"\n#define SUBCOMMANDS_DEEP_CONFIG "tests/subcommands-deep/.cli-flags.toml"\n',
)
api_anchor = r'''  char *resolved_none = f2e_resolve_commands_json_argv_from_file(SUBCOMMANDS_CONFIG, "[\"gitish\",\"--verbose\"]");
  expect_contains("resolve commands empty path", resolved_none, "{\"path\":[],\"label\":\"\"}");
  f2e_free(resolved_none);
'''
api_block = r'''  char *resolved_none = f2e_resolve_commands_json_argv_from_file(SUBCOMMANDS_CONFIG, "[\"gitish\",\"--verbose\"]");
  expect_contains("resolve commands empty path", resolved_none, "{\"path\":[],\"label\":\"\"}");
  f2e_free(resolved_none);

  char *resolved_aliases = f2e_resolve_commands_json_argv_from_file(
      SUBCOMMANDS_DEEP_CONFIG,
      "[\"tool\",\"workspace\",\"remotes\",\"create\",\"annotate\"]");
  expect_json("resolve nested aliases returns canonical path", resolved_aliases,
              "{\"path\":[\"ws\",\"remote\",\"add\",\"tag\"],\"label\":\"ws remote add tag\"}");

  char *structured_aliases = f2e_parse_structured_json_argv_from_file(
      SUBCOMMANDS_DEEP_CONFIG,
      "[\"tool\",\"workspace\",\"remotes\",\"create\",\"annotate\",\"--name\",\"v2\"]");
  expect_contains("structured aliases report canonical command", structured_aliases,
                  "\"command\":\"ws remote add tag\"");
  expect_contains("structured aliases report canonical subcommands", structured_aliases,
                  "\"subcommands\":[\"ws\",\"remote\",\"add\",\"tag\"]");
  expect_contains("structured aliases retain scoped flags", structured_aliases,
                  "\"TOOL_TAG_NAME\":\"v2\"");
  f2e_free(structured_aliases);

  char *alias_help = f2e_help_table_for_json_argv_from_file(
      SUBCOMMANDS_DEEP_CONFIG,
      "tool",
      "[\"tool\",\"workspace\",\"remotes\",\"create\",\"annotate\",\"--help\"]",
      110);
  expect_contains("alias help renders canonical command path", alias_help,
                  "Command: tool ws remote add tag [OPTIONS]");
  f2e_free(alias_help);
'''
replace_exact(api, api_anchor, api_block)

# CLI parse regression for deep aliases.
run_sh = repo / "tests/run.sh"
run_anchor = r'''run_deep_case "{\"TOOL_COMMAND\":\"ws remote add tag\",\"TOOL_CMD_TAG\":\"true\",\"TOOL_DRY_RUN\":\"false\",\"TOOL_TAG_NAME\":\"v1\",\"TOOL_TAG_DRY_RUN\":\"true\",$DEEP_BASE_POSITIONALS}" tool ws remote add tag --name v1 -n
'''
run_block = r'''run_deep_case "{\"TOOL_COMMAND\":\"ws remote add tag\",\"TOOL_CMD_TAG\":\"true\",\"TOOL_DRY_RUN\":\"false\",\"TOOL_TAG_NAME\":\"v1\",\"TOOL_TAG_DRY_RUN\":\"true\",$DEEP_BASE_POSITIONALS}" tool ws remote add tag --name v1 -n
# aliases at every level resolve to the same canonical command path and marker
run_deep_case "{\"TOOL_COMMAND\":\"ws remote add tag\",\"TOOL_CMD_TAG\":\"true\",\"TOOL_DRY_RUN\":\"false\",\"TOOL_TAG_NAME\":\"v2\",\"TOOL_TAG_DRY_RUN\":\"true\",$DEEP_BASE_POSITIONALS}" tool workspace remotes create annotate --name v2 -n
'''
replace_exact(run_sh, run_anchor, run_block)

invalid = repo / "tests/audit-invalid-subcommand/.cli-flags.toml"
append_once(
    invalid,
    '[commands.commit]\naliases = ["commit"]',
    '''# Invalid on purpose: an alias must not redundantly repeat its command's
# canonical name because it creates duplicate help/completion candidates.
[commands.commit]
aliases = ["commit"]''',
)

expected_old = r'''expected='{"ok":false,"errorCount":3,"warningCount":0,"errors":["commands.add env \"GIT_CMD_ADD\" collides with flags.marker env","commands.add and commands.stage share a name or alias","flags.all and flags.everything both use short flag \"A\""],"warnings":[]}' '''.rstrip()
expected_new = r'''expected='{"ok":false,"errorCount":4,"warningCount":0,"errors":["commands.add env \"GIT_CMD_ADD\" collides with flags.marker env","commands.add and commands.stage share a name or alias","commands.commit alias \"commit\" duplicates its canonical name","flags.all and flags.everything both use short flag \"A\""],"warnings":[]}' '''.rstrip()
replace_exact(run_sh, expected_old, expected_new)

# Keep the dedicated shell workflow sensitive to the deep-alias fixtures.
workflow = repo / ".github/workflows/shell-contract.yml"
text = workflow.read_text(encoding="utf-8")
for section_marker in ('      - "tests/subcommands/.cli-flags.toml"\n',):
    occurrences = text.count(section_marker)
    if occurrences != 2:
        raise RuntimeError(f"{workflow}: expected two path-filter occurrences, found {occurrences}")
    text = text.replace(
        section_marker,
        section_marker
        + '      - "tests/subcommands-deep/.cli-flags.toml"\n'
        + '      - "tests/completion/**"\n',
    )
step_anchor = r'''      - name: Upload shell contract diagnostics
'''
step_block = r'''      - name: Exercise command-alias scope and value-consumption regressions
        shell: bash
        run: |
          set -euo pipefail
          bash tests/completion/run.bash

      - name: Upload shell contract diagnostics
'''
if text.count(step_anchor) != 1:
    raise RuntimeError(f"{workflow}: upload step anchor changed")
text = text.replace(step_anchor, step_block)
workflow.write_text(text, encoding="utf-8")

# User-facing contract documentation.
append_once(
    repo / "README.md",
    "### Command aliases are canonicalized",
    r'''
### Command aliases are canonicalized

A command can declare one or more aliases at any nesting depth. The parser
accepts the alias but reports the canonical command path through
`parse.command_env`, structured parsing, and `f2e_resolve_commands`:

```toml
[parse]
command_env = "ZED_COMMAND"

[commands.develop]
aliases = ["dev"]

[commands.develop.commands.shell]
aliases = ["sh"]
```

`zed dev sh` therefore selects the canonical path `develop shell`. Help keeps
the canonical command visible while listing accepted aliases, and generated
Bash/Zsh completion maps every alias to the same canonical option scope.
Separated option values are consumed before command matching, so a value such
as `--profile dev` never activates the `develop` command accidentally.

`flags2env audit` rejects sibling name/alias collisions, unsafe alias tokens,
and aliases that redundantly repeat their own canonical command name.
''',
)

print("patched parser copies:")
for path in parser_paths:
    print(f"  {path}")
