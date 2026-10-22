import 'dart:async';
import 'dart:typed_data';

import 'package:core/src/chunking/chunk_id.dart';
import 'package:core/src/crypto/account_keys.dart';
import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/errors.dart';
import 'package:core/src/format/durability.dart';
import 'package:core/src/format/segment.dart';
import 'package:core/src/pipeline/segment_encoder.dart';
import 'package:core/src/snapshot/chunk_sink.dart';
import 'package:core/src/storage/fragment_store.dart';
import 'package:core/src/storage/local_index.dart';
import 'package:core/src/storage/placement.dart';

/// Отмена длительной операции.
final class CancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  /// [CancelledException], если отменено.
  void check() {
    if (_cancelled) throw const CancelledException();
  }
}

/// [ChunkSink] конвейера бэкапа (задача 1.6.3): дедупликация по локальному
/// индексу, упаковка новых чанков в сегменты до 16 МиБ, шифрование и
/// кодирование ([SegmentEncoder]), запись n фрагментов на узлы по
/// [placeFragments]. Сегмент сохранён, если записано не меньше
/// `minStoredFragments` (t + 1, durability.md); иначе бэкап падает.
///
/// Память ограничена: одновременно обрабатывается не больше
/// [maxInFlight] сегментов, следующий [add] ждёт — это обратное давление
/// на чтение файлов.
final class SegmentPacker implements ChunkSink {
  new({
    required this.crypto,
    required this.keys,
    required this.index,
    required this.store,
    required this.encoder,
    required this.params,
    this.maxInFlight = 2,
    CancellationToken? cancel,
  }) : cancel = cancel ?? CancellationToken() {
    if (maxInFlight < 1) throw ArgumentError.value(maxInFlight, 'maxInFlight');
  }

  final CryptoProvider crypto;
  final AccountKeys keys;
  final LocalIndex index;
  final FragmentStore store;
  final SegmentEncoder encoder;
  final DurabilityParameters params;
  final int maxInFlight;
  final CancellationToken cancel;

  final List<PackedChunk> _open = [];
  final Set<ChunkId> _openIds = {};
  int _openBytes = 0;

  /// Чанки запечатанных сегментов, ещё не записанных в индекс.
  final Set<ChunkId> _flying = {};
  final Set<Future<void>> _inFlight = {};
  (Object, StackTrace)? _failure;

  int segmentsStored = 0;
  int bytesStored = 0;

  int get segmentsInFlight => _inFlight.length;

  @override
  bool contains(ChunkId id) =>
      _openIds.contains(id) ||
      _flying.contains(id) ||
      index.findChunk(id) != null;

  @override
  Future<bool> add(ChunkId id, ChunkType type, Uint8List data) async {
    cancel.check();
    _rethrow();
    if (contains(id)) return false;
    if (_open.isNotEmpty &&
        !SegmentPlaintext.fits(_open.length + 1, _openBytes + data.length)) {
      await _seal();
    }
    _open.add(PackedChunk(id: id, type: type, data: data));
    _openIds.add(id);
    _openBytes += data.length;
    return true;
  }

  /// Запечатывает последний сегмент и ждёт записи всех.
  Future<void> flush() async {
    cancel.check();
    if (_open.isNotEmpty) await _seal();
    await Future.wait(_inFlight.toList());
    _rethrow();
  }

  /// Ждёт уже начатые сегменты, не запечатывая открытый; ошибки
  /// игнорируются (вызывается при отмене и сбое). Недописанные сегменты
  /// остаются «готовящимися» и отбрасываются следующим бэкапом.
  Future<void> abandon() async {
    _open.clear();
    _openIds.clear();
    await Future.wait([for (final f in _inFlight) f.catchError((_) {})]);
  }

  Future<void> _seal() async {
    final chunks = List<PackedChunk>.of(_open);
    _open.clear();
    _flying.addAll(_openIds);
    _openIds.clear();
    _openBytes = 0;
    while (_inFlight.length >= maxInFlight) {
      await Future.any(_inFlight.toList());
      _rethrow();
    }
    cancel.check();
    late final Future<void> task;
    task = _process(chunks)
        .catchError((Object e, StackTrace s) => _failure ??= (e, s))
        .whenComplete(() => _inFlight.remove(task));
    _inFlight.add(task);
  }

  Future<void> _process(List<PackedChunk> chunks) async {
    final plaintext = SegmentPlaintext.encode(chunks);
    final segmentId = crypto.randomBytes(32);
    final key = keys.segmentKey(segmentId);
    final EncodedSegment encoded;
    try {
      encoded = await encoder.encode(
        SegmentJob(
          segmentId: segmentId,
          segmentKey: key,
          plaintext: plaintext,
          k: params.k,
          n: params.n,
        ),
      );
    } finally {
      key.dispose();
    }
    final toc = <SegmentChunk>[];
    var offset = 0;
    for (final c in chunks) {
      toc.add(
        SegmentChunk(
          chunkId: c.id,
          type: c.type.code,
          offset: offset,
          length: c.data.length,
        ),
      );
      offset += c.data.length;
    }
    index.addSegment(
      SegmentEntry(
        segmentId: segmentId,
        k: params.k,
        n: params.n,
        blobLength: encoded.blobLength,
        shardSize: encoded.shardSize,
        fragmentIds: encoded.fragmentIds,
        chunks: toc,
      ),
    );
    _flying.removeAll(chunks.map((c) => c.id));

    final nodes = placeFragments(segmentId, store.nodes, params.n);
    final written = await Future.wait([
      for (var i = 0; i < params.n; i++)
        store
            .put(
              nodes[i],
              encoded.fragments[i],
              expectedFragmentId: encoded.fragmentIds[i],
            )
            .then((_) => true, onError: (Object _) => false),
    ]);
    final ok = written.where((w) => w).length;
    if (ok < params.minStoredFragments) {
      throw InsufficientShardsException(
        available: ok,
        required: params.minStoredFragments,
        segmentId: segmentId,
      );
    }
    index.transaction(() {
      for (var i = 0; i < params.n; i++) {
        if (written[i]) index.setFragmentNode(segmentId, i, nodes[i]);
      }
      index.markSegmentStored(segmentId);
    });
    segmentsStored++;
    bytesStored += plaintext.length;
  }

  void _rethrow() {
    final failure = _failure;
    if (failure != null) Error.throwWithStackTrace(failure.$1, failure.$2);
  }
}
