import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const cli = process.env.F2E_TEST_CLI ?? resolve(dirname(fileURLToPath(import.meta.url)), '../build/flags2env');
const config = `
[env]
files = []
[parse]
allow_unknown = false
allow_separated_values = true
unknown_options_env = "NEG_UNKNOWN"
errors_env = "NEG_ERRORS"
positionals_env = "NEG_POSITIONALS"
[flags.json]
env = "NEG_JSON"
aliases = ["json", "structured"]
type = "bool"
default = "true"
[flags.verbose]
env = "NEG_VERBOSE"
aliases = ["verbose"]
type = "bool"
default = "false"
[flags.output]
env = "NEG_OUTPUT"
aliases = ["output"]
type = "string"
[flags.port]
env = "NEG_PORT"
aliases = ["port"]
type = "integer"
default = 80
[flags.interactive]
env = "NEG_INTERACTIVE"
aliases = ["interactive"]
type = "bool"
requires_tty = true
default = "false"
`;

function parse(args, extra = '', env = {}) {
  const cwd = mkdtempSync(join(tmpdir(), 'flags2env-negation-'));
  try {
    writeFileSync(join(cwd, '.cli-flags.toml'), config + extra);
    const result = spawnSync(cli, ['app', ...args], {
      cwd, encoding: 'utf8', timeout: 10000, maxBuffer: 1024 * 1024,
      // Discovery intentionally refuses $HOME/.cli-flags.toml.
      env: { PATH: process.env.PATH, HOME: join(cwd, 'isolated-home'), FLAGS2ENV_DOTENV: '0', CI: '1',
        F2E_FORCE_STDIN_TTY: '0', F2E_FORCE_STDERR_TTY: '0', F2E_FORCE_CI: '1', ...env },
    });
    assert.ifError(result.error);
    assert.equal(result.status, 0, result.stderr);
    return JSON.parse(result.stdout);
  } finally {
    rmSync(cwd, { recursive: true, force: true });
  }
}
function list(result, key) { return JSON.parse(result[key] ?? '[]'); }
function clean(result) {
  assert.deepEqual(list(result, 'NEG_UNKNOWN'), []);
  assert.deepEqual(list(result, 'NEG_ERRORS'), []);
}

for (const flag of ['--no-json', '--!json', '--json!']) {
  test(`${flag} disables a true default`, () => {
    const result = parse([flag]); clean(result); assert.equal(result.NEG_JSON, 'false');
  });
  test(`${flag} is idempotent, not a toggle`, () => {
    const result = parse([flag, flag]); clean(result); assert.equal(result.NEG_JSON, 'false');
  });
  test(`positive assignment after ${flag} wins`, () => {
    const result = parse([flag, '--json']); clean(result); assert.equal(result.NEG_JSON, 'true');
  });
  test(`${flag} after positive assignment wins`, () => {
    const result = parse(['--json', flag]); clean(result); assert.equal(result.NEG_JSON, 'false');
  });
  test(`${flag} does not consume a separated boolean word`, () => {
    const result = parse([flag, 'true']); clean(result);
    assert.equal(result.NEG_JSON, 'false');
    assert.ok(list(result, 'NEG_POSITIONALS').includes('true'));
  });
  test(`${flag} overrides an ambient true value`, () => {
    const result = parse([flag], '', { NEG_JSON: 'true' }); clean(result);
    assert.equal(result.NEG_JSON, 'false');
  });
  test(`${flag} remains literal after the end marker`, () => {
    const result = parse(['--', flag]); clean(result);
    assert.equal(result.NEG_JSON, 'true');
    assert.ok(list(result, 'NEG_POSITIONALS').includes(flag));
  });
}
for (const flag of ['--!structured', '--structured!']) {
  test(`${flag} resolves a declared long alias`, () => {
    const result = parse([flag]); clean(result); assert.equal(result.NEG_JSON, 'false');
  });
}
for (const flag of ['--!verbose', '--verbose!']) {
  test(`${flag} leaves an already false boolean false`, () => {
    const result = parse([flag]); clean(result); assert.equal(result.NEG_VERBOSE, 'false');
  });
}
for (const flag of ['--!!json', '--json!!', '--!json!', '--!', '--!missing', '--missing!', '--!output', '--output!', '--!port', '--port!', '--no-json!']) {
  test(`${flag} is not admitted as boolean negation`, () => {
    const result = parse([flag]);
    assert.ok(list(result, 'NEG_UNKNOWN').includes(flag));
    assert.equal(result.NEG_JSON, 'true');
  });
}
for (const flag of ['--!json=true', '--!json=false', '--json!=true', '--json!=false', '--json!=']) {
  test(`${flag} reports an error without assignment`, () => {
    const result = parse([flag]);
    assert.ok(list(result, 'NEG_ERRORS').some(value => value.includes('attached value')));
    assert.equal(result.NEG_JSON, 'true');
  });
}
for (const flag of ['--!interactive', '--interactive!']) {
  test(`${flag} does not demand a terminal when disabling interaction`, () => {
    const result = parse([flag]); clean(result); assert.equal(result.NEG_INTERACTIVE, 'false');
  });
}
test('inline string values containing bangs are untouched', () => {
  const result = parse(['--output=--!json']); clean(result);
  assert.equal(result.NEG_OUTPUT, '--!json'); assert.equal(result.NEG_JSON, 'true');
});
test('explicit false remains supported', () => {
  const result = parse(['--json=false']); clean(result); assert.equal(result.NEG_JSON, 'false');
});
test('legacy no-prefix attached-value semantics are preserved', () => {
  const result = parse(['--no-json=true']); clean(result); assert.equal(result.NEG_JSON, 'false');
});
test('exact no-prefixed declared alias retains precedence', () => {
  const extra = '\n[flags.other]\nenv = "NEG_OTHER"\naliases = ["no-json"]\ntype = "bool"\n';
  const result = parse(['--no-json'], extra); clean(result);
  assert.equal(result.NEG_OTHER, 'true'); assert.equal(result.NEG_JSON, 'true');
});
test('child command booleans can be negated in their active scope', () => {
  const extra = '\n[commands.audit]\nenv = "NEG_AUDIT"\n[commands.audit.flags.check]\nenv = "NEG_CHECK"\naliases = ["check"]\ntype = "bool"\ndefault = "true"\n';
  for (const flag of ['--!check', '--check!']) {
    const result = parse(['audit', flag], extra); clean(result); assert.equal(result.NEG_CHECK, 'false');
  }
});
test('overlong option names cannot be truncated into an accepted flag', () => {
  // F2E_MAX_NAME is 96; remain below F2E_MAX_VALUE so this specifically
  // exercises name admission rather than diagnostic-list byte capacity.
  const alias = 'j'.repeat(95);
  const extra = `\n[flags.boundary]\nenv = "NEG_BOUNDARY"\naliases = ["${alias}"]\ntype = "bool"\ndefault = "false"\n`;
  for (const token of [`--${alias}x`, `--${alias}x=true`, `--${'j'.repeat(128)}!`]) {
    const result = parse([token], extra);
    assert.ok(list(result, 'NEG_UNKNOWN').includes(token));
    assert.equal(result.NEG_JSON, 'true');
    assert.equal(result.NEG_BOUNDARY, 'false');
  }
});
