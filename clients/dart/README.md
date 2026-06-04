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
