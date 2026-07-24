import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _ParseNative = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _ParseDart = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _ParseDefaultNative = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _ParseDefaultDart = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _ParseProcessNative = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _ParseProcessDart = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _ParseProcessDefaultNative = Pointer<Utf8> Function();
typedef _ParseProcessDefaultDart = Pointer<Utf8> Function();
typedef _FreeNative = Void Function(Pointer<Utf8>);
typedef _FreeDart = void Function(Pointer<Utf8>);
typedef _IsHelpNative = Int32 Function(Pointer<Utf8>);
typedef _IsHelpDart = int Function(Pointer<Utf8>);
typedef _HelpForArgvNative = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Int32);
typedef _HelpForArgvDart = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, int);
typedef _HelpForArgvFromFileNative = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Int32);
typedef _HelpForArgvFromFileDart = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, int);
typedef _CoerceNative = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _CoerceDart = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _CoerceFromFileNative = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _CoerceFromFileDart = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _GenerateNative = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _GenerateDart = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _GenerateFromFileNative = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef _GenerateFromFileDart = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);

class CoercionError extends Error {
  CoercionError(this.errors);

  final List<String> errors;

  @override
  String toString() => 'flags2env could not coerce config: ${errors.join('; ')}';
}

class Flags2Env {
  Flags2Env._(DynamicLibrary library)
      : _library = library,
        _parseJsonArgvFromFile = library.lookupFunction<_ParseNative, _ParseDart>(
          'f2e_parse_json_argv_from_file',
        ),
        _parseJsonArgv = library.lookupFunction<_ParseDefaultNative, _ParseDefaultDart>(
          'f2e_parse_json_argv',
        ),
        _parseProcessFromFile = library.lookupFunction<_ParseProcessNative, _ParseProcessDart>(
          'f2e_parse_process_from_file',
        ),
        _parseProcess = library.lookupFunction<_ParseProcessDefaultNative, _ParseProcessDefaultDart>(
          'f2e_parse_process',
        ),
        _free = library.lookupFunction<_FreeNative, _FreeDart>('f2e_free');

  final DynamicLibrary _library;
  final _ParseDart _parseJsonArgvFromFile;
  final _ParseDefaultDart _parseJsonArgv;
  final _ParseProcessDart _parseProcessFromFile;
  final _ParseProcessDefaultDart _parseProcess;
  final _FreeDart _free;

  DynamicLibrary get nativeLibrary => _library;

  factory Flags2Env.load([String? libraryPath]) {
    return Flags2Env._(DynamicLibrary.open(libraryPath ?? _defaultLibraryPath()));
  }

  Map<String, String> parse(List<String> argv, {String? configPath}) {
    final encodedArgv = jsonEncode(argv.map((value) => value.toString()).toList()).toNativeUtf8();
    final Pointer<Utf8> result;

    if (configPath == null) {
      result = _parseJsonArgv(encodedArgv);
    } else {
      final config = configPath.toNativeUtf8();
      result = _parseJsonArgvFromFile(config, encodedArgv);
      calloc.free(config);
    }
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
    final Pointer<Utf8> result;

    if (configPath == null) {
      result = _parseProcess();
    } else {
      final config = configPath.toNativeUtf8();
      result = _parseProcessFromFile(config);
      calloc.free(config);
    }

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
