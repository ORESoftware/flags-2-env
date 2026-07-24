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
        _isHelpJsonArgv = library.lookupFunction<_IsHelpNative, _IsHelpDart>(
          'f2e_is_help_requested_json_argv',
        ),
        _helpTableForJsonArgv = library.lookupFunction<_HelpForArgvNative, _HelpForArgvDart>(
          'f2e_help_table_for_json_argv',
        ),
        _helpTableForJsonArgvFromFile = library.lookupFunction<_HelpForArgvFromFileNative, _HelpForArgvFromFileDart>(
          'f2e_help_table_for_json_argv_from_file',
        ),
        _coerceJson = library.lookupFunction<_CoerceNative, _CoerceDart>('f2e_coerce_json'),
        _coerceJsonFromFile = library.lookupFunction<_CoerceFromFileNative, _CoerceFromFileDart>(
          'f2e_coerce_json_from_file',
        ),
        _generateTypes = library.lookupFunction<_GenerateNative, _GenerateDart>('f2e_generate_types'),
        _generateTypesFromFile = library.lookupFunction<_GenerateFromFileNative, _GenerateFromFileDart>(
          'f2e_generate_types_from_file',
        ),
        _free = library.lookupFunction<_FreeNative, _FreeDart>('f2e_free');

  final DynamicLibrary _library;
  final _ParseDart _parseJsonArgvFromFile;
  final _ParseDefaultDart _parseJsonArgv;
  final _ParseProcessDart _parseProcessFromFile;
  final _ParseProcessDefaultDart _parseProcess;
  final _IsHelpDart _isHelpJsonArgv;
  final _HelpForArgvDart _helpTableForJsonArgv;
  final _HelpForArgvFromFileDart _helpTableForJsonArgvFromFile;
  final _CoerceDart _coerceJson;
  final _CoerceFromFileDart _coerceJsonFromFile;
  final _GenerateDart _generateTypes;
  final _GenerateFromFileDart _generateTypesFromFile;
  final _FreeDart _free;

  DynamicLibrary get nativeLibrary => _library;

  factory Flags2Env.load([String? libraryPath]) {
    return Flags2Env._(DynamicLibrary.open(libraryPath ?? _defaultLibraryPath()));
  }

  /// Binds against an already-loaded library, e.g.
  /// `Flags2Env.fromLibrary(DynamicLibrary.process())` when the native core
  /// is statically linked into the host binary (Flutter on iOS).
  factory Flags2Env.fromLibrary(DynamicLibrary library) {
    return Flags2Env._(library);
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

  bool isHelpRequested(List<String> argv) {
    final encodedArgv = jsonEncode(argv.map((value) => value.toString()).toList()).toNativeUtf8();
    final requested = _isHelpJsonArgv(encodedArgv);
    calloc.free(encodedArgv);
    return requested != 0;
  }

  /// Renders the help table for the `[commands.*]` path selected by [argv];
  /// with no matching command this renders the top-level menu, including the
  /// Commands section when subcommands are declared.
  String helpTableForArgv(String command, List<String> argv, {String? configPath, int terminalColumns = 0}) {
    final encodedCommand = command.toNativeUtf8();
    final encodedArgv = jsonEncode(argv.map((value) => value.toString()).toList()).toNativeUtf8();
    final Pointer<Utf8> result;

    if (configPath == null) {
      result = _helpTableForJsonArgv(encodedCommand, encodedArgv, terminalColumns);
    } else {
      final config = configPath.toNativeUtf8();
      result = _helpTableForJsonArgvFromFile(config, encodedCommand, encodedArgv, terminalColumns);
      calloc.free(config);
    }
    calloc.free(encodedCommand);
    calloc.free(encodedArgv);

    if (result == nullptr) {
      return '';
    }
    try {
      return result.toDartString();
    } finally {
      _free(result);
    }
  }

  /// Coerces declared env keys (including subcommand flag envs, command
  /// marker envs, and the command path env) to their declared types.
  Map<String, Object?> coerce(Map<String, Object?> values, {String? configPath}) {
    final payload = jsonEncode(values).toNativeUtf8();
    final Pointer<Utf8> result;

    if (configPath == null) {
      result = _coerceJson(payload);
    } else {
      final config = configPath.toNativeUtf8();
      result = _coerceJsonFromFile(config, payload);
      calloc.free(config);
    }
    calloc.free(payload);

    if (result == nullptr) {
      throw CoercionError(const ['coercion failed']);
    }
    final Map<String, dynamic> report;
    try {
      report = jsonDecode(result.toDartString()) as Map<String, dynamic>;
    } finally {
      _free(result);
    }
    if (report['ok'] != true) {
      final errors = (report['errors'] as List<dynamic>? ?? const []).map((error) => error.toString()).toList();
      throw CoercionError(errors);
    }
    return (report['value'] as Map<String, dynamic>? ?? const {}).map(MapEntry.new);
  }

  /// Generates importable types; subcommand flag envs and command envs are
  /// included as optional fields.
  String generateTypes(String language, {String? typeName, String? configPath}) {
    final encodedLanguage = language.toNativeUtf8();
    final encodedTypeName = typeName?.toNativeUtf8();
    final Pointer<Utf8> result;

    if (configPath == null) {
      result = _generateTypes(encodedLanguage, encodedTypeName ?? nullptr);
    } else {
      final config = configPath.toNativeUtf8();
      result = _generateTypesFromFile(config, encodedLanguage, encodedTypeName ?? nullptr);
      calloc.free(config);
    }
    calloc.free(encodedLanguage);
    if (encodedTypeName != null) {
      calloc.free(encodedTypeName);
    }

    if (result == nullptr) {
      throw ArgumentError('could not generate $language types; check the language, type name, and config audit');
    }
    try {
      return result.toDartString();
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
