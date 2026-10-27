import 'dart:async';
import 'dart:typed_data';

import 'package:core/src/chunking/chunk_id.dart';
import 'package:core/src/crypto/account_keys.dart';
import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/errors.dart';
import 'package:core/src/format/fragment.dart';
import 'package:core/src/format/segment.dart';
import 'package:core/src/storage/fragment_store.dart';
import 'package:core/src/storage/local_index.dart';
import 'package:core/src/storage/placement.dart';
import 'package:core/src/util/bytes.dart';

/// Проблема с отдельным фрагментом: не найден, недоступен или испорчен.
final class FragmentProblem {
  const new({
    required this.segmentId,
    required this.index,
    required this.node,
    required this.error,
  });

  final Uint8List segmentId;
  final int index;

  /// `null` — узел неизвестен и фрагмент не найден ни на одном.
  final String? node;
  final CoreException error;

  @override
  String toString() =>
      'сегмент ${bytesToHex(segmentId).substring(0, 16)}, фрагмент $index'
      '${node == null ? '' : ' на $node'}: ${error.message}';
}

/// Чтение сегментов с узлов (data-format.md, раздел 5, «Восстановление
/// сегмента»): любые k фрагментов, каждый проверяется по `fragment_id` из
/// индекса; сегмент расшифровывается, разбирается, каждый чанк сверяется
/// со своим `chunk_id`. Последние [cacheSize] сегментов кешируются.
///
/// С [locator] перед чтением сегмента спрашивается `LocateSegment`: он
/// даёт талоны GET и текущие узлы фрагментов (после ремонта они могут
/// отличаться от записанных в индексе). Без него узлы — из индекса, а
/// неизвестные ищутся на всех узлах.
///
/// **Запас на медленные** (задача 3.9.3): сначала запрашиваются k
/// фрагментов параллельно, неудачный заменяется следующим. Когда половина
/// из k пришла, а запрос идёт дольше [hedgeFactor] медианы пришедших,
/// параллельно запрашивается ещё один фрагмент — не больше [spare] сверх
/// k. Сегмент собирается из первых k проверенных.
final class SegmentReader {
  new({
    required this.crypto,
    required this.keys,
    required this.index,
    required this.store,
    this.locator,
    this.cacheSize = 2,
    this.spare = 2,
    this.hedgeFactor = 2,
    this.hedgeMinimum = const Duration(milliseconds: 500),
  }) : _hasher = ChunkIdHasher(crypto, keys.chunkIdKey);

  final CryptoProvider crypto;
  final AccountKeys keys;
  final LocalIndex index;
  final FragmentStore store;
  final SegmentLocator? locator;
  final int cacheSize;

  /// Сколько фрагментов сверх k можно запросить у медленных узлов.
  final int spare;

  /// Медленный запрос — дольше медианы пришедших во столько раз.
  final double hedgeFactor;

  /// И не короче этого: на быстрой сети разброс мал.
  final Duration hedgeMinimum;
  final ChunkIdHasher _hasher;

  final Map<String, Map<ChunkId, Uint8List>> _cache = {};

  /// Проблемные фрагменты, встреченные при чтении.
  final List<FragmentProblem> problems = [];

  int segmentsFetched = 0;

  /// Открытый текст чанка. Чанка нет в индексе — [StorageException].
  Future<Uint8List> chunk(ChunkId id) async {
    final location = index.findChunk(id);
    if (location == null || !location.stored) {
      throw StorageException(
        location: 'chunk $id',
        problem: StorageProblem.notFound,
        operation: 'restore',
      );
    }
    final chunks = await segment(location.segmentId);
    final data = chunks[id];
    if (data == null) {
      throw IntegrityException(
        object: 'segment',
        check: IntegrityCheck.objectId,
        objectId: location.segmentId,
      );
    }
    return data;
  }

  /// Чанки сегмента по идентификатору (с проверкой каждого).
  Future<Map<ChunkId, Uint8List>> segment(Uint8List segmentId) async {
    final key = bytesToHex(segmentId);
    final cached = _cache.remove(key);
    if (cached != null) return _cache[key] = cached;
    final blob = await fetchBlob(segmentId);
    final segmentKey = keys.segmentKey(segmentId);
    final Uint8List plain;
    try {
      plain = SegmentCipher.open(
        crypto,
        segmentKey: segmentKey,
        segmentId: segmentId,
        blob: blob,
      );
    } finally {
      segmentKey.dispose();
    }
    final chunks = <ChunkId, Uint8List>{};
    for (final c in SegmentPlaintext.parse(plain)) {
      if (_hasher.of(c.data) != c.id) {
        throw IntegrityException(
          object: 'chunk',
          check: IntegrityCheck.hash,
          objectId: c.id.bytes,
        );
      }
      chunks[c.id] = c.data;
    }
    segmentsFetched++;
    _cache[key] = chunks;
    if (_cache.length > cacheSize) _cache.remove(_cache.keys.first);
    return chunks;
  }

  /// Блоб сегмента из любых k проверенных фрагментов.
  Future<Uint8List> fetchBlob(Uint8List segmentId) async {
    final entry = index.segment(segmentId);
    if (entry == null) {
      throw StorageException(
        location: 'segment ${bytesToHex(segmentId)}',
        problem: StorageProblem.notFound,
        operation: 'restore',
      );
    }
    await resolveNodes(segmentId);
    final candidates = index.fragments(segmentId);
    final valid = await _gather(segmentId, candidates, entry.k);
    if (valid.length < entry.k) {
      throw InsufficientShardsException(
        available: valid.length,
        required: entry.k,
        segmentId: segmentId,
      );
    }
    // Каждый фрагмент уже проверен в fetch по fragment_id из индекса.
    return decodeFragments(
      crypto,
      valid.sublist(0, entry.k),
      segmentId: segmentId,
      verified: true,
    );
  }

  /// Записывает в локальный индекс узлы фрагментов сегмента по ответу
  /// [locator]; без него ничего не делает. Фрагменты, которых нет в
  /// ответе, остаются на прежних узлах.
  Future<void> resolveNodes(Uint8List segmentId) async {
    final locator = this.locator;
    if (locator == null) return;
    final nodes = await locator.locate(segmentId);
    if (nodes.isEmpty) return;
    index.transaction(() {
      for (final f in index.fragments(segmentId)) {
        if (nodes[f.number] case final String node when node != f.node) {
          index.setFragmentNode(segmentId, f.number, node);
        }
      }
    });
  }

  /// Первые [k] проверенных фрагментов из [candidates]: k запросов
  /// параллельно, замена неудачных, запас на медленные (см. класс).
  Future<List<Fragment>> _gather(
    Uint8List segmentId,
    List<FragmentEntry> candidates,
    int k,
  ) async {
    final valid = <Fragment>[];
    final took = <Duration>[];
    final running = <Stopwatch>{};
    final done = Completer<void>();
    var next = 0;
    var extra = 0;
    Timer? hedge;

    void finish() {
      hedge?.cancel();
      if (!done.isCompleted) done.complete();
    }

    late void Function() fill;
    void start() {
      final f = candidates[next++];
      final watch = Stopwatch()..start();
      running.add(watch);
      unawaited(
        fetch(segmentId, f).then((fragment) {
          running.remove(watch);
          if (done.isCompleted) return;
          if (fragment != null) {
            valid.add(fragment);
            took.add(watch.elapsed);
          }
          fill();
        }),
      );
    }

    fill = () {
      if (valid.length >= k) return finish();
      while (running.length < k - valid.length + extra &&
          next < candidates.length) {
        start();
      }
      if (running.isEmpty) finish();
    };

    void check() {
      if (extra >= spare ||
          next >= candidates.length ||
          took.length * 2 < k ||
          running.isEmpty) {
        return;
      }
      final sorted = [...took]..sort();
      final median = sorted[sorted.length ~/ 2];
      var limit = median * hedgeFactor;
      if (limit < hedgeMinimum) limit = hedgeMinimum;
      if (running.any((w) => w.elapsed > limit)) {
        extra++;
        start();
      }
    }

    fill();
    if (!done.isCompleted && spare > 0) {
      hedge = Timer.periodic(const Duration(milliseconds: 100), (_) => check());
    }
    await done.future;
    return valid.sublist(0, valid.length < k ? valid.length : k);
  }

  /// Один фрагмент с проверкой; ошибка — `null` и запись в [problems].
  Future<Fragment?> fetch(Uint8List segmentId, FragmentEntry f) async {
    var node = f.node;
    try {
      node ??= await _locate(f.fragmentId);
      if (node == null) {
        throw StorageException(
          location: 'fragment ${bytesToHex(f.fragmentId)}',
          problem: StorageProblem.notFound,
          operation: 'locate',
        );
      }
      final fragment = Fragment.parse(await store.get(node, f.fragmentId))
        ..verify(crypto, expectedFragmentId: f.fragmentId);
      if (fragment.header.index != f.number) {
        throw IntegrityException(
          object: 'fragment',
          check: IntegrityCheck.fragmentId,
          objectId: segmentId,
        );
      }
      return fragment;
    } on CoreException catch (e) {
      problems.add(
        FragmentProblem(
          segmentId: segmentId,
          index: f.number,
          node: node,
          error: e,
        ),
      );
      return null;
    }
  }

  /// Узел, где лежит фрагмент, если его не знают ни индекс, ни [locator]
  /// (без координатора — после восстановления индекса на новом
  /// устройстве): обход всех узлов.
  Future<String?> _locate(Uint8List fragmentId) async {
    if (locator != null) return null;
    for (final node in store.nodes) {
      try {
        if ((await store.has(node, [fragmentId])).single) return node;
      } on StorageException {
        continue;
      }
    }
    return null;
  }
}
