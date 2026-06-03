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

const cli = f2e.parseProcess();
const combined = { ...process.env, ...cli };
```

### Bun

```js
import * as f2e from "@oresoftware/cli/bun";

const cli = f2e.parseProcess();
const combined = { ...process.env, ...cli };
```

### Deno

```ts
import * as f2e from "./clients/deno/mod.ts";

function getEnvMap(): Record<string, string> {
  return f2e.applyProcess();
}

const combined = getEnvMap();
```

### C

```c
#include "clients/c/lib.h"
#include <stdio.h>

F2EMap get_env_map(char *envp[]) {
  F2EMap combined = {0};

  if (!f2e_client_apply_process_envp(envp, &combined)) {
    return (F2EMap){0};
  }

  return combined;
}

int main(int argc, const char *const argv[], char *envp[]) {
  (void)argc;
  (void)argv;

  F2EMap combined = get_env_map(envp);
  printf("PORT=%s\n", f2e_map_get(&combined, "PORT"));
  f2e_map_free(&combined);
  return 0;
}
```

### Dart

```dart
import 'dart:io';
import 'package:flags2env/flags2env.dart';

Map<String, String> getEnvMap() {
  final f2e = Flags2Env.load('./build/libflags2env.dylib');
  final cli = f2e.parseProcess();
  return <String, String>{...Platform.environment, ...cli};
}

void main() {
  final combined = getEnvMap();
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

func getEnvMap() (map[string]string, error) {
	combined := map[string]string{}
	for _, entry := range os.Environ() {
		key, value, ok := strings.Cut(entry, "=")
		if ok {
			combined[key] = value
		}
	}

	cli, err := flags2env.ParseProcess()
	if err != nil {
		return nil, err
	}
	for key, value := range cli {
		combined[key] = value
	}
	return combined, nil
}

func main() {
	combined, err := getEnvMap()
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
  flags2env:apply_process(flags2env:env_map()).

main(_Args) ->
  Combined = get_env_map(),
  Combined.
```

### Gleam

```gleam
import gleam/dict.{type Dict}
import flags2env

pub fn get_env_map() -> Dict(String, String) {
  flags2env.apply_process(flags2env.env_map())
}

pub fn main() {
  let _combined = get_env_map()
  Nil
}
```

### Elixir

```elixir
defmodule MyApp do
  def get_env_map do
    Flags2Env.apply_process(System.get_env())
  end

  def main(_args) do
    combined = get_env_map()
    combined
  end
end
```

### Java

```java
import com.oresoftware.flags2env.Flags2Env;
import java.util.Map;

public final class Main {
  private static Map<String, String> getEnvMap() {
    return Flags2Env.applyProcess(System.getenv());
  }

  public static void main(String[] args) {
    Map<String, String> combined = getEnvMap();
  }
}
```

### Python

```python
import os
from clients.python.lib import Flags2Env

f2e = Flags2Env("./build/libflags2env.dylib")
cli = f2e.parse_process()
combined = {**os.environ, **cli}
```

### Ruby

```ruby
require_relative "clients/ruby/lib"

cli = Flags2Env.parse_process
combined = ENV.to_h.merge(cli)
```

### PHP

```php
<?php
require __DIR__ . '/clients/php/lib.php';

$f2e = new Flags2Env(__DIR__ . '/build/libflags2env.dylib');
$cli = $f2e->parseProcess();
$combined = array_replace($_ENV, $cli);
```

### Rust

```rust
use flags2env::Flags2Env;
use std::collections::HashMap;
use std::env;

fn get_env_map() -> Result<HashMap<String, String>, Box<dyn std::error::Error>> {
    let sdk = unsafe { Flags2Env::load(Some("./build/libflags2env.dylib"))? };
    let mut combined: HashMap<String, String> = env::vars().collect();

    sdk.apply_process(&mut combined)?;
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

let f2e = try Flags2Env(libraryPath: "./build/libflags2env.dylib")
let combined = try f2e.applyProcess(env: ProcessInfo.processInfo.environment)
```

## Parser Notes

The C parser owns config discovery. By default, it walks upward from the current working directory to find the nearest `.cli-flags.toml`, but refuses to use `$HOME/.cli-flags.toml` because that is likely accidental. Runtime clients should not reimplement this lookup; they should pass an explicit `configPath` only when the user asks for one.

Unknown flags are ignored. Defaults from `.cli-flags.toml` are included in the parsed map, so they also override environment values when merged.
