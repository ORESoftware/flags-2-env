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
--no-debug
-d
-dv
```

Every parsed value is returned as a string. Boolean flags return `"true"` or `"false"`.

## Build

```sh
make all
make test
```

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
void f2e_free(char *value);
```

`f2e_parse_process_from_file` asks the host OS for the current process command line. This is available on macOS, Linux, and Windows. `argv_json` is a JSON array of strings for callers that want to pass a manually edited argv. Return values are heap-allocated JSON object strings and must be released with `f2e_free`.

## Runtime Clients

Client sources live under `clients/<runtime>/`. For package publishing, render or copy only the target runtime client plus the C source or a platform-specific native artifact.

```sh
node scripts/render-client.mjs nodejs dist/nodejs
node scripts/render-client.mjs bun dist/bun
```

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

### C

```c
#include "clients/c/lib.h"
#include <stdio.h>

int main(int argc, const char *const argv[], char *envp[]) {
  F2EMap combined = {0};

  (void)argc;
  (void)argv;

  if (!f2e_client_apply_process_envp(envp, &combined)) {
    return 1;
  }

  printf("PORT=%s\n", f2e_map_get(&combined, "PORT"));
  f2e_map_free(&combined);
  return 0;
}
```

### Dart

```dart
import 'dart:io';
import 'package:flags2env/flags2env.dart';

void main() {
  final f2e = Flags2Env.load('./build/libflags2env.dylib');
  final cli = f2e.parseProcess();
  final combined = <String, String>{...Platform.environment, ...cli};
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

func main() {
	combined := map[string]string{}
	for _, entry := range os.Environ() {
		key, value, ok := strings.Cut(entry, "=")
		if ok {
			combined[key] = value
		}
	}

	cli, err := flags2env.ParseProcess()
	if err != nil {
		panic(err)
	}
	for key, value := range cli {
		combined[key] = value
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

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let sdk = unsafe { Flags2Env::load(Some("./build/libflags2env.dylib"))? };
    let mut combined: HashMap<String, String> = env::vars().collect();

    sdk.apply_process(&mut combined)?;
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

The C parser reads `.cli-flags.toml` from `PWD` by default. Runtime clients should pass an explicit `configPath` when a process changes directories or parses flags for another project.

Unknown flags are ignored. Defaults from `.cli-flags.toml` are included in the parsed map, so they also override environment values when merged.
