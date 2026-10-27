import 'dart:convert';
import 'dart:typed_data';

import 'package:core/src/chunking/chunk_id.dart';
import 'package:core/src/crypto/account_keys.dart';
import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/errors.dart';
import 'package:core/src/pipeline/segment_reader.dart';
import 'package:core/src/snapshot/manifest_objects.dart';
import 'package:core/src/snapshot/snapshot_catalog.dart';
import 'package:core/src/storage/fragment_store.dart';
import 'package:core/src/storage/local_index.dart';
import 'package:core/src/storage/object_store.dart';
import 'package:core/src/storage/placement.dart';
import 'package:protocol/protocol.dart' as pb;

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
    final out = BytesBuilder(copy: false);
    for (final id in chunks) {
      out.add(await _reader.chunk(ChunkId(id)));
    }
    final bytes = out.takeBytes();
    final tree = ManifestObjects.parseMessage<pb.Tree>(
      'tree',
      () => pb.Tree.fromBuffer(bytes),
    );
    if (_trees.length >= cacheSize) _trees.remove(_trees.keys.first);
    return _trees[key] = tree;
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
