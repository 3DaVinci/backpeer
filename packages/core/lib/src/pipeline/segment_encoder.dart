import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/crypto/secret_bytes.dart';
import 'package:core/src/crypto/sodium_crypto_provider.dart';
import 'package:core/src/erasure/reed_solomon.dart';
import 'package:core/src/format/fragment.dart';
import 'package:core/src/format/segment.dart';

/// Сегмент, готовый к записи: n фрагментов целиком (заголовок и тело).
final class EncodedSegment {
  const new({
    required this.segmentId,
    required this.blobLength,
    required this.shardSize,
    required this.fragments,
    required this.fragmentIds,
  });

  final Uint8List segmentId;
  final int blobLength;
  final int shardSize;
  final List<Uint8List> fragments;
  final List<Uint8List> fragmentIds;
}

/// Задание на кодирование: открытый текст сегмента и ключ сегмента.
final class SegmentJob {
  const new({
    required this.segmentId,
    required this.segmentKey,
    required this.plaintext,
    required this.k,
    required this.n,
  });

  final Uint8List segmentId;
  final SecretBytes segmentKey;
  final Uint8List plaintext;
  final int k;
  final int n;
}

/// Шифрование сегмента в блоб и кодирование в n фрагментов
/// (data-format.md, разделы 3–5).
abstract interface class SegmentEncoder {
  Future<EncodedSegment> encode(SegmentJob job);

  Future<void> close();
}

EncodedSegment _encode(
  CryptoProvider crypto,
  SegmentJob job,
  Map<(int, int), ReedSolomon> coders,
) {
  final blob = SegmentCipher.seal(
    crypto,
    segmentKey: job.segmentKey,
    segmentId: job.segmentId,
    plaintext: job.plaintext,
  );
  final coder = coders.putIfAbsent((
    job.k,
    job.n,
  ), () => ReedSolomon(job.k, job.n - job.k));
  final fragments = encodeFragments(
    crypto,
    blob: blob,
    segmentId: job.segmentId,
    k: job.k,
    n: job.n,
    coder: coder,
  );
  return EncodedSegment(
    segmentId: job.segmentId,
    blobLength: blob.length,
    shardSize: fragments.first.header.shardSize,
    fragments: [for (final f in fragments) f.bytes],
    fragmentIds: [for (final f in fragments) f.header.fragmentId(crypto)],
  );
}

/// Кодирование в том же isolate — для тестов и слабых устройств.
final class InlineSegmentEncoder implements SegmentEncoder {
  new(this._crypto);

  final CryptoProvider _crypto;
  final Map<(int, int), ReedSolomon> _coders = {};

  @override
  Future<EncodedSegment> encode(SegmentJob job) async =>
      _encode(_crypto, job, _coders);

  @override
  Future<void> close() async {}
}

/// Пул isolate: каждый кодирует свой сегмент целиком (решение 1.4.4).
/// Открытый текст и фрагменты передаются через `TransferableTypedData`;
/// в каждом isolate — свой libsodium.
final class IsolateSegmentEncoder implements SegmentEncoder {
  new _(this._workers);

  /// Запускает [workers] isolate (по умолчанию — число ядер).
  static Future<IsolateSegmentEncoder> start(int workers) async {
    if (workers < 1) throw ArgumentError.value(workers, 'workers');
    final list = <_Worker>[];
    for (var i = 0; i < workers; i++) {
      list.add(await _Worker.spawn());
    }
    return IsolateSegmentEncoder._(list);
  }

  final List<_Worker> _workers;
  final List<Completer<_Worker>> _waiting = [];

  @override
  Future<EncodedSegment> encode(SegmentJob job) async {
    final worker = await _acquire();
    try {
      return await worker.run(job);
    } finally {
      _release(worker);
    }
  }

  Future<_Worker> _acquire() {
    final free = _workers.where((w) => !w.busy).firstOrNull;
    if (free != null) {
      free.busy = true;
      return Future.value(free);
    }
    final c = Completer<_Worker>();
    _waiting.add(c);
    return c.future;
  }

  void _release(_Worker worker) {
    if (_waiting.isNotEmpty) {
      _waiting.removeAt(0).complete(worker);
    } else {
      worker.busy = false;
    }
  }

  @override
  Future<void> close() async {
    for (final w in _workers) {
      w.close();
    }
  }
}

final class _Worker {
  new _(this._isolate, this._send, this._replies);

  static Future<_Worker> spawn() async {
    final replies = ReceivePort();
    final isolate = await Isolate.spawn(_main, replies.sendPort);
    final events = StreamIterator(replies);
    await events.moveNext();
    return _Worker._(isolate, events.current as SendPort, events);
  }

  final Isolate _isolate;
  final SendPort _send;
  final StreamIterator<Object?> _replies;
  bool busy = false;

  Future<EncodedSegment> run(SegmentJob job) async {
    _send.send((
      job.segmentId,
      job.segmentKey.bytes,
      TransferableTypedData.fromList([job.plaintext]),
      job.k,
      job.n,
    ));
    await _replies.moveNext();
    final reply = _replies.current;
    if (reply is (String, String)) {
      throw StateError('Кодирование сегмента: ${reply.$1}\n${reply.$2}');
    }
    final (blobLength, shardSize, fragments, ids) =
        reply! as (int, int, List<TransferableTypedData>, List<Uint8List>);
    return EncodedSegment(
      segmentId: job.segmentId,
      blobLength: blobLength,
      shardSize: shardSize,
      fragments: [for (final f in fragments) f.materialize().asUint8List()],
      fragmentIds: ids,
    );
  }

  void close() {
    _send.send(null);
    _isolate.kill();
  }

  static Future<void> _main(SendPort replies) async {
    final crypto = await SodiumCryptoProvider.load();
    final coders = <(int, int), ReedSolomon>{};
    final inbox = ReceivePort();
    replies.send(inbox.sendPort);
    await for (final message in inbox) {
      if (message == null) break;
      final (segmentId, key, plaintext, k, n) =
          message as (Uint8List, Uint8List, TransferableTypedData, int, int);
      try {
        final secret = SecretBytes.adopt(key);
        final encoded = _encode(
          crypto,
          SegmentJob(
            segmentId: segmentId,
            segmentKey: secret,
            plaintext: plaintext.materialize().asUint8List(),
            k: k,
            n: n,
          ),
          coders,
        );
        secret.dispose();
        replies.send((
          encoded.blobLength,
          encoded.shardSize,
          [
            for (final f in encoded.fragments)
              TransferableTypedData.fromList([f]),
          ],
          encoded.fragmentIds,
        ));
      } on Object catch (e, stack) {
        replies.send(('$e', '$stack'));
      }
    }
    inbox.close();
  }
}
