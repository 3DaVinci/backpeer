// Фаззинг команды аудита на узле (задача 4.1.5): мутации сообщения канала
// CoordinatorChannelMessage с AuditCommand. Узел либо разбирает его и
// отвечает доказательством, либо отказывает CoordinatorException (ответ
// Error в канале) или DataFormatException (канал закрывается) — без
// других исключений и без пометки целого фрагмента повреждённым.
//
//   FS_FUZZ_SECONDS=600 dart test test/audit_fuzz_test.dart
//   FS_FUZZ_RUNS=100000 FS_FUZZ_SEED=7 dart test test/audit_fuzz_test.dart
//
// По умолчанию — 2000 входов на фаззер, seed 1.

import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:node/node.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';

import '../../core/test/support/fuzz.dart';
import 'support.dart';

void main() {
  late CryptoProvider crypto;
  late Directory dir;
  late FragmentStorage storage;
  late Fragment fragment;
  setUpAll(() async {
    crypto = await SodiumCryptoProvider.load();
    dir = Directory.systemTemp.createTempSync('fs-node-audit-fuzz-');
    storage = FragmentStorage.open(
      dir.path,
      crypto: crypto,
      quotaBytes: 1 << 30,
      freeReserveBytes: 0,
      diskAvailable: (_) => null,
    );
    fragment = testFragment(crypto, blobLength: 200000);
    final id = fragmentIdOf(crypto, fragment);
    final incoming = await storage.beginPut(
      fragmentId: id,
      size: fragment.bytes.length,
      accountId: Uint8List(32),
    );
    await incoming.add(fragment.bytes);
    await incoming.commit();
  });
  tearDownAll(() async {
    await storage.close();
    dir.deleteSync(recursive: true);
  });

  test('CoordinatorChannelMessage с AuditCommand', () async {
    final id = fragmentIdOf(crypto, fragment);
    final count = merkleLeafCount(fragment.body.length);
    final samples = [
      for (var i = 0; i < count; i++)
        Uint8List.fromList(
          pb.CoordinatorChannelMessage(
            id: Int64(i + 1),
            audit: pb.AuditCommand(fragmentId: id, blockIndex: i),
          ).writeToBuffer(),
        ),
    ];
    var answered = 0;
    final rejected = await fuzzAsync('audit-command', samples, (input) async {
      final message = ManifestObjects.parseMessage(
        'CoordinatorChannelMessage',
        () => pb.CoordinatorChannelMessage.fromBuffer(input),
      );
      if (!message.hasAudit()) return;
      final reply = await answerAudit(storage, message.audit);
      answered++;
      expect(
        verifyMerkleAuditPath(
          crypto,
          root: fragment.header.bodyRoot,
          leafCount: count,
          index: message.audit.blockIndex,
          block: reply.block,
          path: reply.path,
        ),
        isTrue,
      );
    });
    printOnFailure('отказов: $rejected, ответов: $answered');
    expect(storage.record(id)!.state, FragmentState.stored);
    expect(storage.damagedCount, 0);
  });
}
