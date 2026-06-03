import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _ParseNative = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _ParseDart = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _FreeNative = Void Function(Pointer<Utf8>);
typedef _FreeDart = void Function(Pointer<Utf8>);

class Flags2Env {
  Flags2Env._(this._library)
      : _parseJsonArgvFromFile = _library.lookupFunction<_ParseNative, _ParseDart>(
          'f2e_parse_json_argv_from_file',
        ),
        _free = _library.lookupFunction<_FreeNative, _FreeDart>('f2e_free');

  final DynamicLibrary _library;
  final _ParseDart _parseJsonArgvFromFile;
  final _FreeDart _free;

  factory Flags2Env.load([String? libraryPath]) {
    return Flags2Env._(DynamicLibrary.open(libraryPath ?? _defaultLibraryPath()));
  }

  Map<String, String> parse(List<String> argv, {String? configPath}) {
    final config = (configPath ?? '${Directory.current.path}/.cli-flags.toml').toNativeUtf8();
    final encodedArgv = jsonEncode(argv.map((value) => value.toString()).toList()).toNativeUtf8();
    final result = _parseJsonArgvFromFile(config, encodedArgv);

    calloc.free(config);
    calloc.free(encodedArgv);

    if (result == nullptr) {
      return <String, String>{};
    }

    try {
      final decoded = jsonDecode(result.toDartString()) as Map<String, dynamic>;
      return decoded.map((key, value) => MapEntry(key, value.toString()));
    } finally {
      _free(result);
    }
  }
}

String _defaultLibraryPath() {
  if (Platform.isMacOS) {
    return 'libflags2env.dylib';
  }
  if (Platform.isWindows) {
    return 'flags2env.dll';
  }
  return 'libflags2env.so';
}
