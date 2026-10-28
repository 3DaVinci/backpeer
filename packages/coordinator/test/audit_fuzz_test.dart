// Фаззинг разбора ответа узла на аудит (задача 4.1.5): мутации сообщения
// канала NodeChannelMessage с правильным AuditReply. Координатор либо
// разбирает сообщение и выносит итог, либо отказывает DataFormatException,
// как канал (protocol.md, раздел 4.10). Аудит проходит, только если блок и
// путь совпадают с правильными: подделать доказательство мутацией нельзя.
//
//   FS_FUZZ_SECONDS=600 dart test test/audit_fuzz_test.dart
//   FS_FUZZ_RUNS=100000 FS_FUZZ_SEED=7 dart test test/audit_fuzz_test.dart
//
// По умолчанию — 2000 входов на фаззер, seed 1.

import 'dart:typed_data';

import 'package:coordinator/coordinator.dart';
import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';

import '../../core/test/support/fuzz.dart';
import 'support/fake_nodes.dart' show prove, segmentFragments;

void main() {
  late CryptoProvider crypto;
  setUpAll(() async => crypto = await SodiumCryptoProvider.load());

  test('NodeChannelMessage с AuditReply', () {
    final f = segmentFragments(crypto, 1).first;
    final target = AuditTarget(
      nodeId: Uint8List(32),
      fragmentId: f.header.fragmentId(crypto),
      bodyRoot: f.header.bodyRoot,
      fragmentSize: f.bytes.length,
      recheck: false,
    );
    final count = merkleLeafCount(f.body.length);
    // Блок тела 600 000 / 2 байт — 64 КиБ, образцы — с коротким последним
    // блоком: мутации короче и чаще доходят до проверки пути.
    final good = {
      for (final i in [count - 1, count - 2]) i: prove(crypto, f, i),
    };
    final samples = [
      for (final MapEntry(:key, :value) in good.entries)
        Uint8List.fromList(
          pb.NodeChannelMessage(
            replyTo: Int64(key + 1),
            audit: value,
          ).writeToBuffer(),
        ),
    ];
    var passed = 0;
    final rejected = fuzz('audit-reply', samples, (input) {
      final message = ManifestObjects.parseMessage(
        'NodeChannelMessage',
        () => pb.NodeChannelMessage.fromBuffer(input),
      );
      for (final MapEntry(key: index, value: reply) in good.entries) {
        final outcome = checkAuditReply(crypto, target, index, message);
        if (!outcome.passed) continue;
        passed++;
        expect(message.audit.block, reply.block);
        expect(
          [for (final p in message.audit.path) bytesToHex(p)],
          [for (final p in reply.path) bytesToHex(p)],
        );
      }
    });
    printOnFailure('отказов разбора: $rejected, пройдено: $passed');
  });
}
