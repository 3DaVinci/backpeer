import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:coordinator/coordinator.dart';
import 'package:core/core.dart';
import 'package:protocol/protocol.dart' as pb;

/// Узлы в памяти вместо каналов команд: отвечают на аудит по своим
/// фрагментам, как `answerAudit` узла.
final class FakeNodes implements NodeCommands {
  new(this.crypto);

  final CryptoProvider crypto;
  final online = <String>{};
  final fragments = <String, Map<String, Fragment>>{};

  /// Не отвечают вовремя.
  final silent = <String>{};

  /// Канал закрывается до ответа.
  final dropping = <String>{};

  /// Отвечают соседним блоком.
  final lying = <String>{};

  /// Отказываются от заданий ремонта (`UNAVAILABLE`).
  final refusing = <String>{};

  /// Принятые задания ремонта: исполнитель и команда.
  final repairs = <(String, pb.RepairCommand)>[];
  int sent = 0;

  void add(Uint8List nodeId, Fragment f) =>
      (fragments[bytesToHex(nodeId)] ??= {})[bytesToHex(
            f.header.fragmentId(crypto),
          )] =
          f;

  void remove(Uint8List nodeId, Fragment f) => fragments[bytesToHex(nodeId)]
      ?.remove(bytesToHex(f.header.fragmentId(crypto)));

  @override
  bool isConnected(List<int> nodeId) => online.contains(bytesToHex(nodeId));

  @override
  Future<pb.NodeChannelMessage?> send(
    List<int> nodeId,
    pb.CoordinatorChannelMessage command,
  ) async {
    sent++;
    final node = bytesToHex(nodeId);
    if (silent.contains(node)) throw TimeoutException('нет ответа');
    if (dropping.contains(node)) return null;
    if (command.hasRepair()) {
      if (refusing.contains(node)) {
        return pb.NodeChannelMessage(
          error: pb.Error(code: pb.ErrorCode.ERROR_CODE_UNAVAILABLE),
        );
      }
      repairs.add((node, command.repair));
      return pb.NodeChannelMessage(done: pb.CommandDone());
    }
    final a = command.audit;
    final f = fragments[node]?[bytesToHex(a.fragmentId)];
    if (f == null) {
      return pb.NodeChannelMessage(
        error: pb.Error(code: pb.ErrorCode.ERROR_CODE_NOT_FOUND),
      );
    }
    return pb.NodeChannelMessage(
      audit: prove(crypto, f, a.blockIndex, lie: lying.contains(node)),
    );
  }
}

pb.AuditReply prove(
  CryptoProvider crypto,
  Fragment f,
  int index, {
  bool lie = false,
}) {
  final count = merkleLeafCount(f.body.length);
  Uint8List block(int i) => Uint8List.sublistView(
    f.body,
    i * merkleBlockSize,
    min(f.body.length, (i + 1) * merkleBlockSize),
  );
  final leaves = [
    for (var i = 0; i < count; i++) merkleLeafHash(crypto, block(i)),
  ];
  return pb.AuditReply(
    block: block(lie ? (index + 1) % count : index),
    path: merkleAuditPath(crypto, leaves, index),
  );
}

/// Сегменты блоба 600 000 байт, k = 2, n = 4: тело фрагмента — 5 блоков.
List<Fragment> segmentFragments(CryptoProvider crypto, int seed) {
  final r = Random(seed);
  return encodeFragments(
    crypto,
    blob: Uint8List.fromList(List.generate(600000, (_) => r.nextInt(256))),
    segmentId: Uint8List.fromList(List.generate(32, (_) => r.nextInt(256))),
    k: 2,
    n: 4,
  );
}
