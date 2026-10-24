import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:node/node.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late CryptoProvider crypto;
  late Directory dir;
  setUpAll(() async => crypto = await SodiumCryptoProvider.load());
  setUp(() => dir = Directory.systemTemp.createTempSync('fs-node-daemon-'));
  tearDown(() => dir.deleteSync(recursive: true));

  NodeConfig config({String yaml = ''}) =>
      NodeConfig.parse(yaml, const {}, dataDir: dir.path);

  Future<NodeControlClient> connect() =>
      NodeControlClient.connect(ControlEndpoint.forDataDir(dir.path));

  test('без ключей не запускается и освобождает папку', () async {
    await expectLater(
      NodeDaemon.start(config(), crypto: crypto, handleSignals: false),
      throwsA(isA<NodeIdentityException>()),
    );
    await NodeIdentity.ensureKeys(dir, crypto);
    // С координатором нужен сертификат.
    await expectLater(
      NodeDaemon.start(
        config(yaml: 'coordinator:\n  url: http://127.0.0.1:1'),
        crypto: crypto,
        handleSignals: false,
      ),
      throwsA(isA<NodeIdentityException>()),
    );
    final daemon = await NodeDaemon.start(
      config(),
      crypto: crypto,
      handleSignals: false,
    );
    await daemon.stop();
  });

  test('локальный API: статус, пределы, пауза, остановка', () async {
    await NodeIdentity.ensureKeys(dir, crypto);
    final daemon = await NodeDaemon.start(
      config(yaml: 'storage:\n  quota_bytes: 5000000\n  free_reserve_bytes: 0'),
      crypto: crypto,
      handleSignals: false,
    );
    final fragment = testFragment(crypto, blobLength: 1000);
    final incoming = await daemon.storage.beginPut(
      fragmentId: fragmentIdOf(crypto, fragment),
      size: fragment.bytes.length,
      accountId: Uint8List(32),
    );
    await incoming.add(fragment.bytes);
    await incoming.commit();
    final client = await connect();
    final status = await client.call('status');
    expect(status['nodeId'], bytesToHex(daemon.identity.nodeId));
    expect(status['state'], 'running');
    expect(status['quotaBytes'], 5000000);
    expect(status['usedBytes'], fragment.bytes.length);
    expect(status['fragments'], 1);
    expect(status['damagedFragments'], 0);
    expect(status['freeBytes'], lessThanOrEqualTo(5000000 - 1024 - 96));
    expect(status['coordinator'], isNull);
    expect((await client.call('stats'))['fragmentsChecked'], 0);

    expect(await client.call('limits', {'upload': 1000, 'download': 0}), {
      'uploadBytesPerSecond': 1000,
      'downloadBytesPerSecond': 0,
    });
    expect(daemon.limits.uploadBytesPerSecond, 1000);
    await expectLater(
      client.call('limits', {'upload': -1}),
      throwsA(isA<ControlException>()),
    );
    expect((await client.call('pause'))['state'], 'paused');
    expect(daemon.gate.tryBegin(), isNull);
    expect((await client.call('resume'))['state'], 'running');
    expect((await client.call('stats'))['activeTransfers'], 0);
    await expectLater(
      client.call('nope'),
      throwsA(
        isA<ControlException>().having((e) => e.code, 'code', 'unknown_method'),
      ),
    );

    expect((await client.call('stop'))['state'], 'stopping');
    await daemon.done.timeout(const Duration(seconds: 10));
    await client.close();
    expect(File('${dir.path}/run/control.sock').existsSync(), isFalse);
    final log = File('${dir.path}/logs/node.log').readAsLinesSync();
    final events = [
      for (final l in log) (jsonDecode(l) as Map<String, Object?>)['event'],
    ];
    expect(events, containsAllInOrder(['started', 'paused', 'stopped']));
  });

  test('остановка ждёт начатую передачу, новые не начинаются', () async {
    await NodeIdentity.ensureKeys(dir, crypto);
    final daemon = await NodeDaemon.start(
      config(),
      crypto: crypto,
      handleSignals: false,
    );
    final transfer = daemon.gate.tryBegin()!;
    var stopped = false;
    unawaited(daemon.stop().then((_) => stopped = true));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(stopped, isFalse);
    expect(daemon.state, NodeState.stopping);
    expect(daemon.gate.tryBegin(), isNull);
    final client = await connect();
    expect((await client.call('status'))['state'], 'stopping');
    await client.close();
    transfer.end();
    await daemon.done.timeout(const Duration(seconds: 5));
    expect(stopped, isTrue);
  });

  test('не дольше shutdown.grace_seconds', () async {
    await NodeIdentity.ensureKeys(dir, crypto);
    final daemon = await NodeDaemon.start(
      config(yaml: 'shutdown:\n  grace_seconds: 0'),
      crypto: crypto,
      handleSignals: false,
    );
    daemon.gate.tryBegin();
    await daemon.stop().timeout(const Duration(seconds: 5));
  });

  group('отдельный процесс', () {
    late String nodeBin;
    setUpAll(() {
      nodeBin = File('bin/node.dart').absolute.path;
    });

    Future<Process> startNode() => Process.start(
      Platform.resolvedExecutable,
      ['run', nodeBin, 'run', '--data', dir.path],
      environment: {'FS_NODE_LOG_FILE': '-'},
    );

    Future<void> waitForSocket() async {
      final socket = File('${dir.path}/run/control.sock');
      for (var i = 0; i < 600 && !socket.existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(socket.existsSync(), isTrue, reason: 'демон не запустился');
    }

    test(
      'SIGTERM: корректная остановка; второй демон на ту же папку — отказ',
      () async {
        await NodeIdentity.ensureKeys(dir, crypto);
        final node = await startNode();
        final log = StringBuffer();
        final logDone = node.stderr.transform(utf8.decoder).forEach(log.write);
        unawaited(node.stdout.drain<void>());
        await waitForSocket();

        final second = await Process.run(Platform.resolvedExecutable, [
          'run',
          nodeBin,
          'run',
          '--data',
          dir.path,
        ]);
        expect(second.exitCode, 1);
        expect('${second.stderr}', contains('занята другим демоном'));

        // Работающий демон второй запуск не задел.
        final client = await connect();
        expect((await client.call('status'))['state'], 'running');
        await client.close();

        expect(node.kill(), isTrue);
        expect(await node.exitCode.timeout(const Duration(seconds: 20)), 0);
        await logDone;
        expect('$log', contains('"event":"stopping","reason":"SIGTERM"'));
        expect('$log', contains('"event":"stopped"'));
        expect(File('${dir.path}/run/control.sock').existsSync(), isFalse);
      },
      skip: Platform.isWindows ? 'SIGTERM' : false,
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}
