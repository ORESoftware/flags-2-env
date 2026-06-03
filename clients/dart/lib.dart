import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _ParseNative = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _ParseDart = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _ParseProcessNative = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _ParseProcessDart = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _FreeNative = Void Function(Pointer<Utf8>);
typedef _FreeDart = void Function(Pointer<Utf8>);

class Flags2Env {
  Flags2Env._(DynamicLibrary library)
      : _library = library,
        _parseJsonArgvFromFile = library.lookupFunction<_ParseNative, _ParseDart>(
          'f2e_parse_json_argv_from_file',
        ),
        _parseProcessFromFile = library.lookupFunction<_ParseProcessNative, _ParseProcessDart>(
          'f2e_parse_process_from_file',
        ),
        _free = library.lookupFunction<_FreeNative, _FreeDart>('f2e_free');

  final DynamicLibrary _library;
  final _ParseDart _parseJsonArgvFromFile;
  final _ParseProcessDart _parseProcessFromFile;
  final _FreeDart _free;

  DynamicLibrary get nativeLibrary => _library;

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

  Map<String, String> parseProcess({String? configPath}) {
    final config = (configPath ?? '${Directory.current.path}/.cli-flags.toml').toNativeUtf8();
    final result = _parseProcessFromFile(config);
    calloc.free(config);

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
