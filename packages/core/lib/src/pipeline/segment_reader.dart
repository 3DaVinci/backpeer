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
/// со своим `chunk_id`. Последние [cacheSize] сегментов кешируются. Узлы
/// фрагментов, которых не знает локальный индекс, спрашиваются у
/// [locator] (`LocateSegment`), а без него ищутся на всех узлах.
final class SegmentReader {
  new({
    required this.crypto,
    required this.keys,
    required this.index,
    required this.store,
    this.locator,
    this.cacheSize = 2,
  }) : _hasher = ChunkIdHasher(crypto, keys.chunkIdKey);

  final CryptoProvider crypto;
  final AccountKeys keys;
  final LocalIndex index;
  final FragmentStore store;
  final SegmentLocator? locator;
  final int cacheSize;
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
    final valid = <Fragment>[];
    var next = 0;
    while (valid.length < entry.k && next < candidates.length) {
      final wave = candidates.sublist(
        next,
        (next + entry.k - valid.length).clamp(0, candidates.length),
      );
      next += wave.length;
      final results = await Future.wait(wave.map((f) => fetch(segmentId, f)));
      valid.addAll(results.whereType<Fragment>());
    }
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

  /// Записывает в локальный индекс узлы фрагментов сегмента, которых он
  /// не знает, по ответу [locator]; без него или если все узлы известны —
  /// ничего не делает.
  Future<void> resolveNodes(Uint8List segmentId) async {
    final locator = this.locator;
    if (locator == null) return;
    final unknown = [
      for (final f in index.fragments(segmentId))
        if (f.node == null) f.number,
    ];
    if (unknown.isEmpty) return;
    final nodes = await locator.locate(segmentId);
    index.transaction(() {
      for (final number in unknown) {
        if (nodes[number] case final String node) {
          index.setFragmentNode(segmentId, number, node);
        }
      }
    });
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
