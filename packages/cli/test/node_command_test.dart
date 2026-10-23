import 'dart:convert';
import 'dart:io';

import 'package:cli/cli.dart';
import 'package:core/core.dart';
import 'package:node/node.dart';
import 'package:test/test.dart';

final class _Console implements Console {
  final List<String> lines = [];
  final List<String> errors = [];

  @override
  void out(String line) => lines.add(line);

  @override
  void err(String line) => errors.add(line);

  @override
  String? ask(String prompt) => null;

  @override
  String? askSecret(String prompt) => null;

  @override
  void progress(String line) {}
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('fs-cli-node-'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<(int, Map<String, Object?>, _Console)> cli(List<String> args) async {
    final console = _Console();
    final code = await runCli(
      ['--json', ...args],
      console: console,
      environment: {
        'FS_HOME': '${dir.path}/home',
        'FS_NODE_DATA_DIR': '${dir.path}/node',
      },
    );
    return (
      code,
      jsonDecode(console.lines.last) as Map<String, Object?>,
      console,
    );
  }

  test('демон не запущен — ошибка с папкой данных', () async {
    final (code, result, _) = await cli(['node', 'status']);
    expect(code, ExitCode.error);
    expect(result['message'], contains('не запущен'));
    expect(result['message'], contains('${dir.path}/node'));
  });

  test('status, limits, pause, resume, stop через локальный API', () async {
    final crypto = await SodiumCryptoProvider.load();
    final data = Directory('${dir.path}/node');
    await NodeIdentity.ensureKeys(data, crypto);
    final daemon = await NodeDaemon.start(
      NodeConfig.parse('', const {}, dataDir: data.path),
      crypto: crypto,
      handleSignals: false,
    );

    var (code, result, _) = await cli(['node', 'status']);
    expect(code, ExitCode.ok);
    expect(result['nodeId'], bytesToHex(daemon.identity.nodeId));
    expect(result['state'], 'running');

    (code, result, _) = await cli(['node', 'limits', '--upload', '2048']);
    expect(result['uploadBytesPerSecond'], 2048);
    expect(result['downloadBytesPerSecond'], 0);
    (code, result, _) = await cli(['node', 'limits', '--download', 'x']);
    expect(code, ExitCode.usage);

    (code, result, _) = await cli(['node', 'pause']);
    expect(result['state'], 'paused');
    (code, result, _) = await cli(['node', 'stats']);
    expect(result['activeTransfers'], 0);
    (code, result, _) = await cli(['node', 'resume']);
    expect(result['state'], 'running');

    // Текст для человека.
    final console = _Console();
    await runCli(
      ['node', 'status', '--node-data', data.path],
      console: console,
      environment: {'FS_HOME': '${dir.path}/home'},
    );
    expect(console.lines.first, contains('работает'));
    expect(console.lines.join('\n'), contains('отдача 2.0 КиБ/с'));

    (code, result, _) = await cli(['node', 'stop']);
    expect(result['state'], 'stopping');
    await daemon.done.timeout(const Duration(seconds: 10));
  });
}
