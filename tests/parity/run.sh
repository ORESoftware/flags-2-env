#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
CLI="$ROOT_DIR/build/flags2env"
FIXTURE_DIR="$ROOT_DIR/tests/fixtures"

missing_tools=""
for tool in node python3 ruby bash; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    missing_tools="${missing_tools:+$missing_tools }$tool"
  fi
done

if [ "$missing_tools" ]; then
  printf 'flags2env parity tests skipped; missing reference parser tools: %s\n' "$missing_tools"
  exit 0
fi

run_ours() {
  (cd "$FIXTURE_DIR" && "$CLI" "$@")
}

expect_same() {
  label="$1"
  expected="$2"
  actual="$3"
  if [ "$actual" != "$expected" ]; then
    printf '%s parity mismatch\nExpected: %s\nActual:   %s\n' "$label" "$expected" "$actual" >&2
    exit 1
  fi
}

node_reference() {
  node - "$@" <<'NODE'
const { parseArgs } = require("node:util");

const parsed = parseArgs({
  args: process.argv.slice(2),
  allowPositionals: true,
  strict: true,
  options: {
    port: { type: "string", short: "p" },
    "listen-port": { type: "string" },
    host: { type: "string", short: "h" },
    debug: { type: "boolean", short: "d" },
    verbose: { type: "boolean", short: "v" },
    color: { type: "boolean", short: "c" },
    mode: { type: "string", short: "m" },
    env: { type: "string" },
  },
});

const values = parsed.values;
const out = {
  PORT: "3000",
  DEBUG: "false",
  COLOR: "true",
};

if (values.port !== undefined) out.PORT = String(values.port);
if (values["listen-port"] !== undefined) out.PORT = String(values["listen-port"]);
if (values.debug !== undefined) out.DEBUG = values.debug ? "true" : "false";
if (values.color !== undefined) out.COLOR = values.color ? "true" : "false";
if (values.host !== undefined) out.HOST = String(values.host);
if (values.verbose !== undefined) out.VERBOSE = values.verbose ? "true" : "false";
if (values.mode !== undefined) out.NODE_ENV = String(values.mode);
if (values.env !== undefined) out.NODE_ENV = String(values.env);

process.stdout.write(JSON.stringify(out));
NODE
}

python_reference() {
  python3 - "$@" <<'PY'
import argparse
import json
import sys

parser = argparse.ArgumentParser(add_help=False, allow_abbrev=False)
parser.add_argument("--port", "--listen-port", "-p", dest="port")
parser.add_argument("--host", "-h", dest="host")
parser.add_argument("--debug", "-d", dest="debug", action="store_true", default=None)
parser.add_argument("--no-debug", dest="debug", action="store_false")
parser.add_argument("--verbose", "-v", dest="verbose", action="store_true", default=None)
parser.add_argument("--color", "-c", dest="color", action="store_true", default=None)
parser.add_argument("--no-color", dest="color", action="store_false")
parser.add_argument("--mode", "--env", "-m", dest="mode")
values, _ = parser.parse_known_args(sys.argv[1:])

out = {
    "PORT": "3000",
    "DEBUG": "false",
    "COLOR": "true",
}
if values.port is not None:
    out["PORT"] = str(values.port)
if values.debug is not None:
    out["DEBUG"] = "true" if values.debug else "false"
if values.color is not None:
    out["COLOR"] = "true" if values.color else "false"
if values.host is not None:
    out["HOST"] = str(values.host)
if values.verbose is not None:
    out["VERBOSE"] = "true" if values.verbose else "false"
if values.mode is not None:
    out["NODE_ENV"] = str(values.mode)

sys.stdout.write(json.dumps(out, separators=(",", ":")))
PY
}

ruby_reference() {
  ruby -roptparse -rjson - "$@" <<'RUBY'
values = {}

parser = OptionParser.new do |opts|
  opts.on("-p", "--port VALUE", "--listen-port VALUE") { |value| values[:port] = value }
  opts.on("-h", "--host VALUE") { |value| values[:host] = value }
  opts.on("-d", "--debug") { values[:debug] = true }
  opts.on("--no-debug") { values[:debug] = false }
  opts.on("-v", "--verbose") { values[:verbose] = true }
  opts.on("-c", "--[no-]color") { |value| values[:color] = value }
  opts.on("-m", "--mode VALUE", "--env VALUE") { |value| values[:mode] = value }
end

parser.permute!(ARGV)

out = {
  "PORT" => "3000",
  "DEBUG" => "false",
  "COLOR" => "true",
}
out["PORT"] = values[:port].to_s if values.key?(:port)
out["DEBUG"] = values[:debug] ? "true" : "false" if values.key?(:debug)
out["COLOR"] = values[:color] ? "true" : "false" if values.key?(:color)
out["HOST"] = values[:host].to_s if values.key?(:host)
out["VERBOSE"] = values[:verbose] ? "true" : "false" if values.key?(:verbose)
out["NODE_ENV"] = values[:mode].to_s if values.key?(:mode)

STDOUT.write(JSON.generate(out))
RUBY
}

bash_getopts_reference() {
  bash -s -- "$@" <<'BASH'
set -eu

if [ "${1:-}" = "app" ]; then
  shift
fi

port="3000"
debug="false"
color="true"
host=""
host_set=0
verbose=""
verbose_set=0
node_env=""
node_env_set=0

OPTIND=1
while getopts ":p:dh:vcm:" opt; do
  case "$opt" in
    p) port="$OPTARG" ;;
    d) debug="true" ;;
    h) host="$OPTARG"; host_set=1 ;;
    v) verbose="true"; verbose_set=1 ;;
    c) color="true" ;;
    m) node_env="$OPTARG"; node_env_set=1 ;;
    :) exit 2 ;;
    \?) exit 2 ;;
  esac
done

printf '{"PORT":"%s","DEBUG":"%s","COLOR":"%s"' "$port" "$debug" "$color"
if [ "$host_set" -eq 1 ]; then
  printf ',"HOST":"%s"' "$host"
fi
if [ "$verbose_set" -eq 1 ]; then
  printf ',"VERBOSE":"%s"' "$verbose"
fi
if [ "$node_env_set" -eq 1 ]; then
  printf ',"NODE_ENV":"%s"' "$node_env"
fi
printf '}'
BASH
}

compare_node() {
  label="$1"
  shift
  expect_same "$label" "$(node_reference "$@")" "$(run_ours "$@")"
}

compare_python() {
  label="$1"
  shift
  expect_same "$label" "$(python_reference "$@")" "$(run_ours "$@")"
}

compare_ruby() {
  label="$1"
  shift
  expect_same "$label" "$(ruby_reference "$@")" "$(run_ours "$@")"
}

compare_bash_getopts() {
  label="$1"
  shift
  expect_same "$label" "$(bash_getopts_reference "$@")" "$(run_ours "$@")"
}

compare_node "node util.parseArgs long/separated options" \
  app --port=8181 --debug --host 127.0.0.1 -v --mode production

compare_node "node util.parseArgs scans after subcommand positionals" \
  app exec --listen-port 4545 --debug

compare_python "python argparse long aliases and boolean negation" \
  app --port -1 --debug --host=-internal --no-color -v --env staging

compare_python "python argparse scans after subcommand positionals" \
  app exec --listen-port 4545 --debug

compare_ruby "ruby OptionParser short and long options" \
  app -p 9000 --debug --no-color --host ruby.local -v --env dev

compare_ruby "ruby OptionParser scans after subcommand positionals" \
  app exec --listen-port 4545 --debug

compare_bash_getopts "bash getopts short option parity" \
  app -p 7070 -d -h shell.local -v -c -m shell

# Short bundles ("ls -la", "rm -rf", "set -eo pipefail"): boolean-only groups
# and groups whose final flag consumes a value, inline or separated. Every
# reference parser below implements the same getopt rule.
compare_bash_getopts "bash getopts boolean-only bundle" \
  app -dv
compare_bash_getopts "bash getopts bundle with separated value" \
  app -dvp 7071 -m shell
compare_bash_getopts "bash getopts bundle with inline value" \
  app -dvp7072
compare_python "python argparse boolean-only bundle" \
  app -vd --env staging
compare_python "python argparse bundle with separated value" \
  app -dvp 7073
compare_python "python argparse bundle with inline value" \
  app -dvm production
compare_ruby "ruby OptionParser boolean-only bundle" \
  app -dv --env dev
compare_ruby "ruby OptionParser bundle with separated value" \
  app -dvm dev
compare_node "node util.parseArgs boolean-only bundle" \
  app -dv --mode production
compare_node "node util.parseArgs bundle with separated value" \
  app -dvp 7074
compare_node "node util.parseArgs bundle with inline value" \
  app -dvmproduction

printf 'flags2env parity tests passed\n'
