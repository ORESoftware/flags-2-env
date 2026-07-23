import 'dart:convert';

import 'cli_stuff.dart';

void main() {
  final decoded = jsonDecode('''
    {
      "PORT": 4242,
      "RATIO": 0.25,
      "DEBUG": true,
      "NAME": "matrix",
      "ITEMS": [1, "two"],
      "LABELS": {"region": "test"},
      "PAYLOAD": {"enabled": true},
      "UNTYPED": "123"
    }
  ''') as Map<String, dynamic>;

  final config = CliStuff.fromJson(decoded);
  if (config.PORT != 4242 ||
      config.NAME != 'matrix' ||
      config.UNTYPED != '123' ||
      config.LABELS['region'] != 'test') {
    throw StateError('generated Dart config has unexpected values');
  }
  if (config.toJson()['DEBUG'] != true) {
    throw StateError('generated Dart config did not serialize');
  }

  print('dart generated interface passed');
}
