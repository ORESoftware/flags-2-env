# flags-2-env

`flags-2-env` parses CLI flags through a project-local `.cli-flags.toml` file and returns a string-to-string map of environment variable overrides.

The native core is C. Runtime clients bind to the same small ABI and convert the returned JSON object into each language's native map type.

## Config

Create `.cli-flags.toml` in the project root:

```toml
[flags.port]
env = "PORT"
aliases = ["port", "listen-port"]
short = "p"
type = "string"
default = "3000"

[flags.debug]
env = "DEBUG"
aliases = ["debug"]
short = "d"
type = "bool"
default = "false"
true_aliases = ["t", "1"]
false_aliases = ["f", "0"]

[flags.mode]
env = "NODE_ENV"
aliases = ["mode", "env"]
short = "m"
type = "string"
```

This repository's own root `.cli-flags.toml` is intentionally library-shaped for CLI smoke tests and maps to `FLAGS2ENV_*` variables. App-shaped examples like `PORT` and `NODE_ENV` live under `tests/fixtures/`.

Supported CLI forms:

```sh
--port 8080
--port=8080
--listen-port 8080
-p 8080
-p8080
--debug
--debug=false
--debug=t
--debug 0
--no-debug
-d
-d=1
-d0
-dv
```

Every parsed value is returned as a string. Boolean flags return `"true"` or `"false"`. Canonical `true` and `false` are always accepted as boolean values. Shorthand values like `t`, `f`, `1`, and `0` only work when the flag declares them in `true_aliases` or `false_aliases`.

## Build

```sh
make all
make borrow-check
make test
```

`make test` runs the C smoke tests plus `make borrow-check`. The borrow check uses Clang's static analyzer with ownership annotations on heap-returning C APIs, so returned strings must be released through `f2e_free`.

Outputs:

```text
build/libflags2env.dylib  # macOS
build/libflags2env.so     # Linux
build/flags2env.dll       # Windows
build/libflags2env.a
build/flags2env
```

The shared library exposes:

```c
char *f2e_parse_process_from_file(const char *config_path);
char *f2e_parse_json_argv_from_file(const char *config_path, const char *argv_json);
char *f2e_audit_config_from_file(const char *config_path);
void f2e_free(char *value);
```

`f2e_parse_process_from_file` asks the host OS for the current process command line. This is available on macOS, Linux, and Windows. `argv_json` is a JSON array of strings for callers that want to pass a manually edited argv. Return values are heap-allocated JSON object strings and must be released with `f2e_free`.

Audit a config before parsing or in CI:

```sh
build/flags2env audit .cli-flags.toml
scripts/audit-changed-cli-flags.sh
```

The audit fails on ambiguous long aliases, duplicate short flags, duplicate env targets, `--no-*` namespace clashes, and conflicting boolean value aliases.

## Runtime Clients

Client sources live under `clients/<runtime>/`. For package publishing, render or copy only the target runtime client plus the C source or a platform-specific native artifact.

```sh
node scripts/render-client.mjs nodejs dist/nodejs
node scripts/render-client.mjs bun dist/bun
```

BEAM clients share the Erlang NIF in `clients/erlang/flags2env_nif.c`; compile it with Erlang headers plus `src/parser.c` into `priv/flags2env_nif.so`. The Java client uses `clients/java/native/flags2env_jni.c`; compile it with JNI headers plus `src/parser.c` into `libflags2env_jni`.

Node, Bun, and Deno use syntax-highlighted source files instead of `.ejs` templates:

```text
clients/nodejs/lib.mjs
clients/nodejs/lib.cjs
clients/nodejs/lib.ts
clients/bun/lib.mjs
clients/bun/lib.cjs
clients/bun/lib.ts
clients/deno/lib.ts
```

Node package exports include both ESM and CommonJS entrypoints. For webpack, Turbopack, and other bundlers, keep the native addon or shared library external to the browser bundle and load it at runtime.

## Client Tests

Each client has a smoke test and a Dockerfile that runs it on Linux:

```sh
docker build -f clients/nodejs/Dockerfile -t flags2env-nodejs .
docker run --rm flags2env-nodejs
scripts/test-docker-clients.sh nodejs bun deno
```

Swap `nodejs` for `c`, `bun`, `deno`, `dart`, `golang`, `python`, `ruby`, `php`, `rust`, `swift`, `erlang`, `elixir`, `gleam`, or `java`. Docker can test Linux userland and can vary CPU architecture with `--platform`, but it cannot faithfully emulate macOS or Windows kernels; use native CI runners for those.

The repository also includes `.github/workflows/cli-flags-audit.yml`, a GitHub Actions bot that runs when any `.cli-flags.toml` changes and reports audit failures as PR annotations.

## Usage

In every language, the merge rule is:

```text
combined = env map + parsed CLI map
```

When the same key exists in both maps, the parsed CLI value wins.

Most clients expose two parse modes:

```text
parseProcess()  # read the current process argv through the C library
parse(argv)     # explicitly pass argv after slicing, popping, or rewriting
```

### Node.js

```js
import * as f2e from "@oresoftware/cli";

function getEnvMap(argv = process.argv) {
  const envMap = process.env;
  const cli = f2e.parse(argv);
  return { ...envMap, ...cli };
}

const combined = getEnvMap();
```

### Bun

```js
import * as f2e from "@oresoftware/cli/bun";

function getEnvMap(argv = Bun.argv) {
  const envMap = process.env;
  const cli = f2e.parse(argv);
  return { ...envMap, ...cli };
}

const combined = getEnvMap();
```

### Deno

```ts
import * as f2e from "./clients/deno/mod.ts";

function getEnvMap(argv: string[] = Deno.args): Record<string, string> {
  const envMap = f2e.envMap();
  const cli = f2e.parse(argv);
  return { ...envMap, ...cli };
}

const combined = getEnvMap();
```

### C

```c
#include "clients/c/lib.h"
#include <stdio.h>
#include <string.h>

F2EMap env_map_from_envp(char *envp[]) {
  F2EMap env_map = {0};

  for (size_t i = 0; envp[i]; i++) {
    char *eq = strchr(envp[i], '=');
    if (eq) {
      char key[512];
      size_t key_len = (size_t)(eq - envp[i]);
      if (key_len < sizeof(key)) {
        memcpy(key, envp[i], key_len);
        key[key_len] = '\0';
        f2e_map_set(&env_map, key, eq + 1);
      }
    }
  }

  return env_map;
}

F2EMap get_env_map(int argc, const char *const argv[], char *envp[]) {
  F2EMap env_map = env_map_from_envp(envp);
  F2EMap cli = {0};

  if (!f2e_client_parse(argc, argv, &cli)) {
    f2e_map_free(&env_map);
    return (F2EMap){0};
  }

  f2e_map_overlay(&env_map, &cli);
  f2e_map_free(&cli);

  F2EMap combined = env_map;
  return combined;
}

int main(int argc, const char *const argv[], char *envp[]) {
  F2EMap combined = get_env_map(argc, argv, envp);
  printf("PORT=%s\n", f2e_map_get(&combined, "PORT"));
  f2e_map_free(&combined);
  return 0;
}
```

### Dart

```dart
import 'dart:io';
import 'package:flags2env/flags2env.dart';

Map<String, String> getEnvMap(List<String> args) {
  final f2e = Flags2Env.load('./build/libflags2env.dylib');
  final cli = f2e.parse(args);
  return <String, String>{...Platform.environment, ...cli};
}

void main(List<String> args) {
  final combined = getEnvMap(args);
}
```

### Go

```go
package main

import (
	"os"
	"strings"

	flags2env "github.com/oresoftware/flags-2-env/clients/golang"
)

func envMap() map[string]string {
	env := map[string]string{}
	for _, entry := range os.Environ() {
		key, value, ok := strings.Cut(entry, "=")
		if ok {
			env[key] = value
		}
	}
	return env
}

func mergeMaps(env map[string]string, cli map[string]string) map[string]string {
	combined := make(map[string]string, len(env)+len(cli))
	for key, value := range env {
		combined[key] = value
	}
	for key, value := range cli {
		combined[key] = value
	}
	return combined
}

func getEnvMap(args []string) (map[string]string, error) {
	cli, err := flags2env.Parse(args)
	if err != nil {
		return nil, err
	}
	return mergeMaps(envMap(), cli), nil
}

func main() {
	combined, err := getEnvMap(os.Args)
	if err != nil {
		panic(err)
	}
	_ = combined
}
```

### Erlang

```erlang
-module(my_app).
-export([get_env_map/0, main/1]).

get_env_map() ->
  Env = flags2env:env_map(),
  Cli = flags2env:parse(init:get_plain_arguments()),
  maps:merge(Env, Cli).

main(_Args) ->
  Combined = get_env_map(),
  Combined.
```

### Gleam

```gleam
import gleam/dict.{type Dict}
import flags2env

pub fn get_env_map() -> Dict(String, String) {
  let env_map = flags2env.env_map()
  let cli = flags2env.parse([])

  dict.fold(cli, env_map, fn(combined, key, value) {
    dict.insert(combined, key, value)
  })
}

pub fn main() {
  let _combined = get_env_map()
  Nil
}
```

### Elixir

```elixir
defmodule MyApp do
  def get_env_map(args) do
    env_map = System.get_env()
    cli = Flags2Env.parse(args)

    Map.merge(env_map, cli)
  end

  def main(args) do
    combined = get_env_map(args)
    combined
  end
end
```

### Java

```java
import com.oresoftware.flags2env.Flags2Env;
import java.util.Map;
import java.util.stream.Collectors;
import java.util.stream.Stream;

public final class Main {
  private static Map<String, String> getEnvMap(String[] args) {
    Map<String, String> envMap = System.getenv();
    Map<String, String> cli = Flags2Env.parse(args);

    return Stream.concat(envMap.entrySet().stream(), cli.entrySet().stream())
        .collect(Collectors.toMap(
            Map.Entry::getKey,
            Map.Entry::getValue,
            (env, cliValue) -> cliValue
        ));
  }

  public static void main(String[] args) {
    Map<String, String> combined = getEnvMap(args);
  }
}
```

### Python

```python
import os
import sys
from flags2env import Flags2Env

def get_env_map(argv=None):
    sdk = Flags2Env("./build/libflags2env.dylib")
    env_map = dict(os.environ)
    cli = sdk.parse(sys.argv if argv is None else argv)

    return {**env_map, **cli}

combined = get_env_map()
```

### Ruby

```ruby
require_relative "clients/ruby/lib"

def get_env_map(argv = ARGV)
  env_map = ENV.to_h
  cli = Flags2Env.parse(argv)

  env_map.merge(cli)
end

combined = get_env_map
```

### PHP

```php
<?php
require __DIR__ . '/clients/php/lib.php';

$f2e = new Flags2Env(__DIR__ . '/build/libflags2env.dylib');

function get_env_map(Flags2Env $f2e, array $argv): array {
    $envMap = $_ENV;
    $cli = $f2e->parse($argv);

    return array_replace($envMap, $cli);
}

$combined = get_env_map($f2e, $argv);
```

### Rust

```rust
use flags2env::Flags2Env;
use std::collections::HashMap;
use std::env;

fn get_env_map() -> Result<HashMap<String, String>, Box<dyn std::error::Error>> {
    let sdk = unsafe { Flags2Env::load(Some("./build/libflags2env.dylib"))? };
    let env_map: HashMap<String, String> = env::vars().collect();
    let argv: Vec<String> = env::args().collect();
    let cli = sdk.parse(&argv, None)?;

    let combined = env_map.into_iter().chain(cli).collect();
    Ok(combined)
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let combined = get_env_map()?;
    let _ = combined;
    Ok(())
}
```

### Swift

```swift
import Foundation

func getEnvMap(args: [String] = CommandLine.arguments) throws -> [String: String] {
    let f2e = try Flags2Env(libraryPath: "./build/libflags2env.dylib")
    let envMap = ProcessInfo.processInfo.environment
    let cli = try f2e.parse(args)

    return envMap.merging(cli) { _, cli in cli }
}

let combined = try getEnvMap()
```

## Parser Notes

The C parser owns config discovery. By default, it walks upward from the current working directory to find the nearest `.cli-flags.toml`, but refuses to use `$HOME/.cli-flags.toml` because that is likely accidental. Runtime clients should not reimplement this lookup; they should pass an explicit `configPath` only when the user asks for one.

Unknown flags are ignored. Defaults from `.cli-flags.toml` are included in the parsed map, so they also override environment values when merged.
