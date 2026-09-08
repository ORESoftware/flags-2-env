import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync, mkdirSync, copyFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

// One-time implementation carrier. This script is not part of the product PR.
// Refuse any preimage other than the explicitly reviewed source snapshot.
const root = resolve(process.argv[2] ?? '.');
const path = resolve(root, 'src/parser.c');
let source = readFileSync(path, 'utf8');
const bytes = Buffer.from(source);
assert.equal(createHash('sha1').update(`blob ${bytes.length}\0`).update(bytes).digest('hex'),
  '345ecc555019e57e3f25cdb0d6ac579c277b8dcf', 'parser preimage moved');
function once(before, after) {
  assert.equal(source.split(before).length - 1, 1, `ambiguous/missing patch: ${before.slice(0, 90)}`);
  source = source.replace(before, after);
}

const helper = String.raw`/* Negation is resolved in the active command scope, after exact aliases.
   Bang forms are shorthand only for declared booleans. They never toggle a
   previous value, consume a following value, or reinterpret positionals. */
static F2EFlag *f2e_find_negated_bool(F2EConfig *config, int scope,
                                      const char *name, int *bang_form) {
  const char *start = name;
  size_t length = strlen(name);
  *bang_form = 0;
  if (strncmp(name, "no-", 3) == 0) {
    start += 3;
    length -= 3;
  } else if (length > 1 && name[0] == '!') {
    start++;
    length--;
    *bang_form = 1;
  } else if (length > 1 && name[length - 1] == '!') {
    length--;
    *bang_form = 1;
  } else {
    return NULL;
  }
  if (length == 0 || length >= F2E_MAX_NAME) {
    return NULL;
  }
  char alias[F2E_MAX_NAME];
  memcpy(alias, start, length);
  alias[length] = '\0';
  /* Reject doubled/mixed bangs rather than assigning an invented meaning. */
  if (strchr(alias, '!') != NULL) {
    return NULL;
  }
  F2EFlag *flag = f2e_find_flag_by_alias(config, scope, alias);
  return flag && flag->type == F2E_TYPE_BOOL ? flag : NULL;
}

`;
once('static int f2e_token_looks_like_known_option(', helper + 'static int f2e_token_looks_like_known_option(');
once(String.raw`    if (strncmp(copy, "no-", 3) == 0) {
      F2EFlag *flag = f2e_find_flag_by_alias(config, scope, copy + 3);
      return flag && flag->type == F2E_TYPE_BOOL;
    }
    return 0;`, String.raw`    int bang_form = 0;
    return f2e_find_negated_bool(config, scope, copy, &bang_form) != NULL;`);
once(String.raw`  F2EFlag *flag = f2e_find_flag_by_alias(config, scope, name);
  if (!flag && strncmp(name, "no-", 3) == 0) {
    flag = f2e_find_flag_by_alias(config, scope, name + 3);
    if (flag && flag->type == F2E_TYPE_BOOL) {
      negated = 1;
    } else {
      return;
    }
  }`, String.raw`  F2EFlag *flag = f2e_find_flag_by_alias(config, scope, name);
  int bang_form = 0;
  if (!flag) {
    flag = f2e_find_negated_bool(config, scope, name, &bang_form);
    negated = flag != NULL;
  }
  if (flag && bang_form && has_inline_value) {
    f2e_json_list_append(errors,
        "bang-negated boolean flags do not accept an attached value; use --flag=false");
    return;
  }`);

// No token may become a known flag by truncating its name to the fixed buffer.
once(String.raw`    char copy[F2E_MAX_NAME];
    f2e_strlcpy(copy, name, sizeof(copy));
    char *eq = strchr(copy, '=');
    if (eq) {
      *eq = '\0';
    }`, String.raw`    char copy[F2E_MAX_NAME];
    const char *eq = strchr(name, '=');
    size_t length = eq ? (size_t)(eq - name) : strlen(name);
    if (length == 0 || length >= sizeof(copy)) {
      return 0;
    }
    memcpy(copy, name, length);
    copy[length] = '\0';`);
once(String.raw`    if (name_length >= sizeof(name)) {
      name_length = sizeof(name) - 1;
    }`, String.raw`    if (name_length >= sizeof(name)) {
      return;
    }`);
once(String.raw`  } else {
    f2e_strlcpy(name, raw, sizeof(name));
  }

  F2EFlag *flag = f2e_find_flag_by_alias(config, scope, name);`, String.raw`  } else {
    if (strlen(raw) >= sizeof(name)) {
      return;
    }
    f2e_strlcpy(name, raw, sizeof(name));
  }

  F2EFlag *flag = f2e_find_flag_by_alias(config, scope, name);`);
writeFileSync(path, source);

const makefilePath = resolve(root, 'Makefile');
const makefile = readFileSync(makefilePath, 'utf8');
assert.equal(makefile.split('\t./tests/run.sh\n').length, 2);
writeFileSync(makefilePath, makefile.replace('\t./tests/run.sh\n', '\t./tests/run.sh\n\tnode --test tests/negation.test.mjs\n'));
copyFileSync(resolve(dirname(fileURLToPath(import.meta.url)), 'negation.test.mjs'), resolve(root, 'tests/negation.test.mjs'));
mkdirSync(resolve(root, 'docs'), { recursive: true });
writeFileSync(resolve(root, 'docs/boolean-negation.md'), `# Boolean negation\n\nUse \`--no-json\` as the portable, documented spelling for disabling a declared boolean. Git and many other CLIs use the \`--no-\` convention. A boolean declared with \`default = "true"\` can be disabled explicitly.\n\nThe shared C parser also accepts \`'--!json'\` and \`'--json!'\`. Quote bang forms in interactive shells such as Bash, where history expansion may otherwise run before the program receives argv. The quotes are shell syntax, not part of the flag. Completions continue to recommend the portable \`--no-\` form.\n\nAll three spellings assign false; they are not toggles. Repeating a negation stays false. Later argv assignments win: \`--no-json --json\` enables JSON, while \`--json '--!json'\` disables it. These assignments use the normal configured source precedence; an explicit order-of-preference policy is not bypassed.\n\nNegation resolves only a declared boolean in the active scope. It does not create flags, disable strings or integers, cross command scopes, rewrite argument values, or reinterpret anything after \`--\`. Exact declared aliases retain precedence over synthesized negation. Mixed/doubled bangs are rejected as unknown.\n\nBang aliases do not take an attached value: \`--!json=true\` and \`--json!=false\` report parse errors without assigning the flag. Use \`--json=false\` for an explicit value. The historical \`--no-\` behavior is preserved. A separated word after a negation remains a positional rather than being silently consumed.\n\nDisabling a requires_tty boolean remains valid without a terminal. Strict applications must check the parser's unknown-option and error channels; retaining a configured default alongside an error is not successful admission.\n\nThe implementation lives in the common parser, so clients using the native C core inherit it without a CLI-specific argv rewriting layer. Consumers pinned to older commits must update their immutable dependency and rerun their own tests before claiming support.\n\nReferences: https://git-scm.com/docs/gitcli and https://www.gnu.org/software/bash/manual/html_node/History-Interaction.html .\n`);
console.log('Applied exact-preimage negation change to four product files.');
