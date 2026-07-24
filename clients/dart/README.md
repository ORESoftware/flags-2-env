# flags2env Dart

Dart FFI bindings for the native flags2env C ABI.

```dart
import 'package:flags2env/lib.dart';

void main(List<String> args) {
  final flags = Flags2Env.load();
  final env = flags.parse(args);
  print(env);
}
```

The package expects the native `flags2env` shared library to be available on
the platform library path, or you can pass an explicit library path to
`Flags2Env.load()`.

Subcommand-aware APIs mirror the C core: `parse` returns the resolved
`[commands.*]` path under `parse.command_env` (default `FLAGS2ENV_COMMAND`),
`isHelpRequested(argv)` detects `--help`, `helpTableForArgv(command, argv)`
renders the help menu for the subcommand selected by argv, `coerce(values)`
types declared env keys (including command marker envs), and
`generateTypes(language)` emits importable interfaces.

## Flutter

The bindings are plain `dart:ffi`, so they work in Flutter apps on macOS,
Linux, Windows, iOS, and Android. Bundle `libflags2env` with your app and hand
the platform-specific location to `Flags2Env.load(...)`:

- **macOS/Linux/Windows**: ship the dylib/so/dll alongside the executable (for
  macOS, add it to the Runner target's Frameworks) and load it by path.
- **Android**: place per-ABI builds of `libflags2env.so` under
  `android/app/src/main/jniLibs/<abi>/`; `Flags2Env.load('libflags2env.so')`
  then resolves through the system loader.
- **iOS**: link the static library (`libflags2env.a`) into the Runner target
  and use `DynamicLibrary.process()` via
  `Flags2Env.fromLibrary(DynamicLibrary.process())`-style loading, or wrap the
  C sources in a small CocoaPod.

Ship the app's `.cli-flags.toml` as an asset, write it to a real file path at
startup (the native core reads the filesystem), and pass that path as
`configPath`.
