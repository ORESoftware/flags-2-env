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

  const subcommandsConfig = '../../../subcommands/.cli-flags.toml';
  final scoped = f2e.parse(['gitish', 'add', '-A'], configPath: subcommandsConfig);
  if (scoped['GITISH_COMMAND'] != 'add' || scoped['GITISH_ADD_ALL'] != 'true') {
    stderr.writeln('unexpected scoped map: $scoped');
    exit(1);
  }

  if (!f2e.isHelpRequested(['gitish', 'add', '--help']) || f2e.isHelpRequested(['gitish', 'add'])) {
    stderr.writeln('help detection failed');
    exit(1);
  }

  final scopedHelp = f2e.helpTableForArgv(
    'gitish',
    ['gitish', 'remote', 'add', '--help'],
    configPath: subcommandsConfig,
    terminalColumns: 100,
  );
  if (!scopedHelp.contains('Command: gitish remote add [OPTIONS]') || !scopedHelp.contains('--fetch')) {
    stderr.writeln('unexpected scoped help:\n$scopedHelp');
    exit(1);
  }

  final topHelp = f2e.helpTableForArgv('gitish', ['gitish'], configPath: subcommandsConfig, terminalColumns: 100);
  if (!topHelp.contains('Commands:') || !topHelp.contains('remote add')) {
    stderr.writeln('unexpected top-level help:\n$topHelp');
    exit(1);
  }

  final coerced = f2e.coerce(
    {'GITISH_COMMAND': 'remote add', 'GITISH_CMD_ADD': 'true', 'GITISH_REMOTE_ADD_FETCH': 'true'},
    configPath: subcommandsConfig,
  );
  if (coerced['GITISH_COMMAND'] != 'remote add' || coerced['GITISH_CMD_ADD'] != true || coerced['GITISH_REMOTE_ADD_FETCH'] != true) {
    stderr.writeln('unexpected coerced map: $coerced');
    exit(1);
  }

  var coerceRejected = false;
  try {
    f2e.coerce({'GITISH_COMMAND': 42}, configPath: subcommandsConfig);
  } on CoercionError catch (error) {
    coerceRejected = error.toString().contains('command_env');
  }
  if (!coerceRejected) {
    stderr.writeln('expected CoercionError for a numeric command path');
    exit(1);
  }

  final generated = f2e.generateTypes('typescript', typeName: 'GitishConfig', configPath: subcommandsConfig);
  if (!generated.contains('GITISH_COMMAND?: string;') || !generated.contains('GITISH_CMD_ADD?: boolean;')) {
    stderr.writeln('unexpected generated types:\n$generated');
    exit(1);
  }

  stdout.writeln('dart client tests passed');
}
