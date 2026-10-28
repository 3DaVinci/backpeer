import 'dart:convert';
import 'dart:typed_data';

import 'package:core/src/chunking/chunk_id.dart';
import 'package:core/src/crypto/account_keys.dart';
import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/errors.dart';
import 'package:core/src/pipeline/segment_packer.dart';
import 'package:core/src/pipeline/segment_reader.dart';
import 'package:core/src/snapshot/manifest_objects.dart';
import 'package:core/src/snapshot/snapshot_catalog.dart';
import 'package:core/src/storage/fragment_store.dart';
import 'package:core/src/storage/local_index.dart';
import 'package:core/src/storage/object_store.dart';
import 'package:core/src/storage/placement.dart';
import 'package:protocol/protocol.dart' as pb;

/// Найденный поиском путь снимка.
final class SnapshotMatch {
  const new(this.path, this.node);

  /// Имена от корня снимка, как у [SnapshotBrowser.list]; последнее — имя
  /// [node].
  final List<String> path;
  final pb.Node node;
}

/// Итог поиска по имени.
final class SnapshotSearch {
  const new({
    required this.matches,
    required this.truncated,
    required this.scanned,
  });

  final List<SnapshotMatch> matches;

  /// Найдено больше `limit`: показаны первые.
  final bool truncated;

  /// Сколько узлов дерева просмотрено.
  final int scanned;
}

/// Путь в одном из снимков (сравнение версий файла, задача 5.4.1).
final class FileVersion {
  const new({
    required this.snapshot,
    required this.node,
    required this.changed,
  });

  final pb.Snapshot snapshot;

  /// `null` — в этом снимке пути нет.
  final pb.Node? node;

  /// Отличается от предыдущего снимка, где путь был: другое содержимое,
  /// размер или тип. Первое появление — тоже изменение.
  final bool changed;
}

/// Просмотр дерева файлов снимка без восстановления (задачи 5.1.3,
/// 5.4.1): каталог читается, только когда его открыли, — дерево с
/// миллионом файлов не грузится целиком.
///
/// Путь — список имён от корня снимка: первое имя — корень бэкапа, как он
/// записан в снимке (`/home/user/docs`), дальше — имена внутри. Прочитанные
/// каталоги кешируются (не больше [cacheSize]).
final class SnapshotBrowser {
  new({
    required this.crypto,
    required this.keys,
    required this.index,
    required FragmentStore fragments,
    required this.objects,
    SegmentLocator? locator,
    this.cacheSize = 64,
  }) : _reader = SegmentReader(
         crypto: crypto,
         keys: keys,
         index: index,
         store: fragments,
         locator: locator,
       );

  final CryptoProvider crypto;
  final AccountKeys keys;
  final LocalIndex index;
  final ObjectStore objects;
  final int cacheSize;
  final SegmentReader _reader;

  final _snapshots = <String, pb.Snapshot>{};
  final _trees = <String, pb.Tree>{};

  /// Содержимое каталога [path] снимка [snapshotId]; пустой путь — корни
  /// бэкапа. Нет такого пути или это не каталог — [StorageException]
  /// с `notFound`.
  Future<List<pb.Node>> list(Uint8List snapshotId, List<String> path) async {
    final snapshot = await _snapshot(snapshotId);
    final snapKey = bytesKey(snapshotId);
    var tree = await _tree('$snapKey:', snapshot.rootTree);
    final walked = StringBuffer(snapKey);
    for (final name in path) {
      final node = _find(tree, name);
      if (node == null || node.type != pb.NodeType.NODE_TYPE_DIRECTORY) {
        throw StorageException(
          location: path.join('/'),
          problem: StorageProblem.notFound,
          operation: 'browse',
          cause: 'нет такого каталога в снимке',
        );
      }
      walked.write('/$name');
      tree = await _tree('$walked', node.subtree);
    }
    return tree.nodes;
  }

  /// Поиск по имени в снимке [snapshotId] под каталогом [under] (пусто —
  /// весь снимок). [query] без `*` и `?` — часть имени, с ними — шаблон
  /// имени целиком; регистр не важен. Обход читает каталоги мимо кеша, чтобы
  /// не вытеснять открытые; останавливается на [limit] найденных.
  Future<SnapshotSearch> search(
    Uint8List snapshotId,
    String query, {
    List<String> under = const [],
    int limit = 200,
    CancellationToken? cancel,
  }) async {
    final matches = nameMatcher(query);
    final found = <SnapshotMatch>[];
    var scanned = 0;
    // Обход в глубину; стек — каталоги, которые ещё предстоит прочитать.
    final stack = <(List<String>, List<List<int>>?)>[(under, null)];
    while (stack.isNotEmpty) {
      cancel?.check();
      final (path, subtree) = stack.removeLast();
      final nodes = subtree == null
          ? await list(snapshotId, path)
          : (await _read(subtree)).nodes;
      final dirs = <(List<String>, List<List<int>>)>[];
      for (final node in nodes) {
        scanned++;
        final name = utf8.decode(node.name, allowMalformed: true);
        final childPath = [...path, name];
        if (matches(name)) {
          if (found.length == limit) {
            return SnapshotSearch(
              matches: found,
              truncated: true,
              scanned: scanned,
            );
          }
          found.add(SnapshotMatch(childPath, node));
        }
        if (node.type == pb.NodeType.NODE_TYPE_DIRECTORY) {
          dirs.add((childPath, node.subtree));
        }
      }
      // В стек в обратном порядке: каталоги обходятся по порядку имён.
      stack.addAll(dirs.reversed);
    }
    return SnapshotSearch(matches: found, truncated: false, scanned: scanned);
  }

  /// Путь [path] (как у [list], не пустой) во всех [snapshots] по порядку:
  /// есть ли он и изменился ли с предыдущего снимка, где был.
  Future<List<FileVersion>> versions(
    List<pb.Snapshot> snapshots,
    List<String> path, {
    CancellationToken? cancel,
  }) async {
    if (path.isEmpty) throw ArgumentError.value(path, 'path', 'пустой путь');
    final parent = path.sublist(0, path.length - 1);
    final wanted = utf8.encode(path.last);
    final out = <FileVersion>[];
    pb.Node? previous;
    for (final snapshot in snapshots) {
      cancel?.check();
      final id = Uint8List.fromList(snapshot.snapshotId);
      _snapshots.putIfAbsent(bytesKey(id), () => snapshot);
      pb.Node? node;
      try {
        for (final n in await list(id, parent)) {
          if (_same(n.name, wanted)) {
            node = n;
            break;
          }
        }
      } on StorageException catch (e) {
        if (e.problem != StorageProblem.notFound) rethrow;
      }
      out.add(
        FileVersion(
          snapshot: snapshot,
          node: node,
          changed:
              node != null && (previous == null || !_sameNode(previous, node)),
        ),
      );
      if (node != null) previous = node;
    }
    return out;
  }

  /// Проверка имени для [search]: часть имени или шаблон с `*` и `?`.
  static bool Function(String) nameMatcher(String query) {
    final q = query.toLowerCase();
    if (!q.contains('*') && !q.contains('?')) {
      return (name) => name.toLowerCase().contains(q);
    }
    final pattern = StringBuffer('^');
    for (final rune in q.runes) {
      final c = String.fromCharCode(rune);
      pattern.write(switch (c) {
        '*' => '.*',
        '?' => '.',
        _ => RegExp.escape(c),
      });
    }
    pattern.write(r'$');
    final re = RegExp(pattern.toString(), dotAll: true);
    return (name) => re.hasMatch(name.toLowerCase());
  }

  static bool _sameNode(pb.Node a, pb.Node b) {
    if (a.type != b.type || a.size != b.size) return false;
    if (a.type == pb.NodeType.NODE_TYPE_SYMLINK) {
      return _same(a.symlinkTarget, b.symlinkTarget);
    }
    if (a.content.length != b.content.length) return false;
    for (var i = 0; i < a.content.length; i++) {
      if (!_same(a.content[i], b.content[i])) return false;
    }
    return true;
  }

  Future<pb.Snapshot> _snapshot(Uint8List id) async {
    final key = bytesKey(id);
    if (_snapshots[key] case final s?) return s;
    final snapshot = await SnapshotCatalog(
      crypto: crypto,
      manifestKey: keys.manifestKey,
      store: objects,
      index: index,
    ).get(id);
    return _snapshots[key] = snapshot;
  }

  Future<pb.Tree> _tree(String key, List<List<int>> chunks) async {
    if (_trees.remove(key) case final cached?) {
      // В конец — как недавно использованный.
      return _trees[key] = cached;
    }
    final tree = await _read(chunks);
    if (_trees.length >= cacheSize) _trees.remove(_trees.keys.first);
    return _trees[key] = tree;
  }

  Future<pb.Tree> _read(List<List<int>> chunks) async {
    final out = BytesBuilder(copy: false);
    for (final id in chunks) {
      out.add(await _reader.chunk(ChunkId(id)));
    }
    final bytes = out.takeBytes();
    return ManifestObjects.parseMessage<pb.Tree>(
      'tree',
      () => pb.Tree.fromBuffer(bytes),
    );
  }

  static pb.Node? _find(pb.Tree tree, String name) {
    final wanted = utf8.encode(name);
    for (final node in tree.nodes) {
      if (_same(node.name, wanted)) return node;
    }
    return null;
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Ключ кеша для идентификатора.
  static String bytesKey(List<int> id) => base64Url.encode(id);
}
