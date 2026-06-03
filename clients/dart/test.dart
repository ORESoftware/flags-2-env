import 'dart:io';

import 'lib.dart';

void main() {
  final suffix = Platform.isMacOS ? 'dylib' : Platform.isWindows ? 'dll' : 'so';
  final f2e = Flags2Env.load('../../build/libflags2env.$suffix');
  Directory.current = '../../tests/fixtures/nested/deeper';
  final parsed = f2e.parse(['app', '--debug=t', '--port', '8181']);

  if (parsed['DEBUG'] != 'true' || parsed['PORT'] != '8181' || parsed['COLOR'] != 'true') {
    stderr.writeln('unexpected parsed map: $parsed');
    exit(1);
  }

  final explicit = f2e.parse(['app', '--debug=f'], configPath: '../../.cli-flags.toml');
  if (explicit['DEBUG'] != 'false' || explicit['PORT'] != '3000') {
    stderr.writeln('unexpected explicit config map: $explicit');
    exit(1);
  }
}
