import 'dart:async';
import 'dart:typed_data';

import 'package:core/src/chunking/chunk_id.dart';
import 'package:core/src/crypto/account_keys.dart';
import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/errors.dart';
import 'package:core/src/format/durability.dart';
import 'package:core/src/format/fragment.dart';
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
/// кодирование ([SegmentEncoder]), запись n фрагментов на узлы, которые
/// выбрал [placer] (координатор или [placeFragments]), и подтверждение
/// загрузки. Сегмент сохранён, если записано не меньше
/// `minStoredFragments` (t + 1, durability.md); иначе бэкап падает и
/// сегмент не подтверждается.
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
    SegmentPlacer? placer,
    this.maxInFlight = 2,
    CancellationToken? cancel,
  }) : placer = placer ?? LocalPlacer(store),
       cancel = cancel ?? CancellationToken() {
    if (maxInFlight < 1) throw ArgumentError.value(maxInFlight, 'maxInFlight');
  }

  final CryptoProvider crypto;
  final AccountKeys keys;
  final LocalIndex index;
  final FragmentStore store;
  final SegmentEncoder encoder;
  final DurabilityParameters params;
  final SegmentPlacer placer;
  final int maxInFlight;
  final CancellationToken cancel;

  final List<PackedChunk> _open = [];
  final Set<ChunkId> _openIds = {};
  int _openBytes = 0;

  /// Чанки запечатанных сегментов, ещё не записанных в индекс.
  final Set<ChunkId> _flying = {};
  final Set<Future<void>> _inFlight = {};

  /// Запечатанные сегменты, которые ещё не сохранены, и сколько их
  /// фрагментов уже подтвердили узлы: по этому видно долю работы внутри
  /// сегмента, когда файлы давно прочитаны (прогресс бэкапа).
  final Set<_Flying> _flyingSegments = {};
  int _flyingBytes = 0;
  (Object, StackTrace)? _failure;

  /// Байт новых чанков, которые прочитаны, но ещё не сохранены: открытый
  /// сегмент и запечатанные, ждущие узлов (подтверждённые фрагменты уже
  /// не в счёт). Это то, чего не хватает до конца файлов в счётчиках
  /// обхода.
  int get pendingBytes {
    final left = _openBytes + _flyingBytes - _ackedBytes;
    return left < 0 ? 0 : left;
  }

  int get _ackedBytes {
    var bytes = 0;
    for (final f in _flyingSegments) {
      bytes += f.bytes * f.acked ~/ params.n;
    }
    return bytes;
  }

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
    final flying = _Flying(chunks.fold(0, (bytes, c) => bytes + c.data.length));
    _flyingSegments.add(flying);
    _flyingBytes += flying.bytes;
    late final Future<void> task;
    task = _process(chunks, flying)
        .catchError((Object e, StackTrace s) => _failure ??= (e, s))
        .whenComplete(() => _inFlight.remove(task));
    _inFlight.add(task);
  }

  Future<void> _process(List<PackedChunk> chunks, _Flying flying) async {
    try {
      await _store(chunks, flying);
    } finally {
      if (_flyingSegments.remove(flying)) _flyingBytes -= flying.bytes;
    }
  }

  Future<void> _store(List<PackedChunk> chunks, _Flying flying) async {
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

    final targets = await placer.allocate(
      SegmentAllocation(
        segmentId: segmentId,
        k: params.k,
        n: params.n,
        repairThreshold: params.repairThreshold,
        fragmentSize: encoded.fragments.first.length,
        fragmentIds: encoded.fragmentIds,
        bodyRoots: [
          for (final f in encoded.fragments) Fragment.parse(f).header.bodyRoot,
        ],
      ),
    );
    // Ошибки записи не прерывают остальные загрузки, но первая из них
    // объясняет, почему фрагментов не хватило: «нет связи», «исчерпан
    // суточный предел relay» и т. п. Без неё пользователь видел только
    // «доступно фрагментов 0».
    final errors = <CoreException>[];
    final written = await Future.wait([
      for (var i = 0; i < params.n; i++)
        if (targets[i] case final FragmentTarget target)
          store
              .put(
                target.node,
                encoded.fragments[i],
                expectedFragmentId: encoded.fragmentIds[i],
              )
              .then(
                (_) {
                  // Фрагмент лёг: доля работы внутри сегмента растёт, пока
                  // остальные ещё загружаются (прогресс бэкапа).
                  flying.acked++;
                  return true;
                },
                onError: (Object e) {
                  if (e is CoreException) errors.add(e);
                  return false;
                },
              )
        else
          Future.value(false),
    ]);
    final ok = written.where((w) => w).length;
    if (ok < params.minStoredFragments) {
      throw InsufficientShardsException(
        available: ok,
        required: params.minStoredFragments,
        segmentId: segmentId,
        cause: _putCause(errors),
      );
    }
    await placer.commit(segmentId, [
      for (var i = 0; i < params.n; i++)
        if (written[i]) i,
    ]);
    index.transaction(() {
      for (var i = 0; i < params.n; i++) {
        if (written[i]) index.setFragmentNode(segmentId, i, targets[i]!.node);
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

  /// Причина, которую стоит показать: «узел недоступен» важнее прочих
  /// ошибок — она объясняет отказ всех узлов сразу (нет связи, кончился
  /// суточный предел relay).
  static CoreException? _putCause(List<CoreException> errors) {
    for (final e in errors) {
      if (e is StorageException && e.problem == StorageProblem.unavailable) {
        return e;
      }
    }
    return errors.isEmpty ? null : errors.first;
  }
}

/// Запечатанный сегмент, который ещё не сохранён: его байты и сколько
/// фрагментов уже подтвердили узлы.
final class _Flying {
  new(this.bytes);

  final int bytes;
  int acked = 0;
}
