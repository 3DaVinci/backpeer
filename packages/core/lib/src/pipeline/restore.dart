import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/src/chunking/chunk_id.dart';
import 'package:core/src/crypto/account_keys.dart';
import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/errors.dart';
import 'package:core/src/pipeline/segment_packer.dart';
import 'package:core/src/pipeline/segment_reader.dart';
import 'package:core/src/snapshot/fs_entry.dart';
import 'package:core/src/snapshot/fs_writer.dart';
import 'package:core/src/snapshot/manifest_objects.dart';
import 'package:core/src/snapshot/snapshot_catalog.dart';
import 'package:core/src/snapshot/walker.dart';
import 'package:core/src/storage/fragment_store.dart';
import 'package:core/src/storage/local_index.dart';
import 'package:core/src/storage/object_store.dart';
import 'package:core/src/storage/placement.dart';
import 'package:protocol/protocol.dart' as pb;

/// Итог восстановления.
final class RestoreResult {
  int files = 0;
  int directories = 0;
  int symlinks = 0;
  int bytes = 0;
  int segmentsFetched = 0;

  /// Уже существующие пути, которые не перезаписаны (без `overwrite`).
  final List<String> skippedExisting = [];

  /// Пути, которые не удалось восстановить, и причина.
  final List<(String, String)> errors = [];

  /// Метаданные, которые нельзя восстановить: владелец без прав root.
  bool ownersRestored = false;

  bool get isComplete => errors.isEmpty && skippedExisting.isEmpty;
}

/// Восстановление снимка целиком или отдельных путей в [target]
/// (задача 1.6.4). Корни снимка (исходные пути) раскладываются в [target]
/// по полному пути: `/home/u/data` → `<target>/home/u/data`.
///
/// [paths] — выбранные пути в исходном виде (`/home/u/data/sub`); пусто —
/// весь снимок. Существующие файлы не перезаписываются без [overwrite].
/// Ошибки отдельных файлов (например, недоступный сегмент) не прерывают
/// восстановление и попадают в [RestoreResult.errors].
Future<RestoreResult> runRestore({
  required CryptoProvider crypto,
  required AccountKeys keys,
  required LocalIndex index,
  required FragmentStore fragments,
  required ObjectStore objects,
  required Uint8List snapshotId,
  required Directory target,
  SegmentLocator? locator,
  List<String> paths = const [],
  bool overwrite = false,
  CancellationToken? cancel,
  FileSystemWriter? writer,
}) async {
  final catalog = SnapshotCatalog(
    crypto: crypto,
    manifestKey: keys.manifestKey,
    store: objects,
    index: index,
  );
  final snapshot = await catalog.get(snapshotId);
  final restorer = _Restorer(
    reader: SegmentReader(
      crypto: crypto,
      keys: keys,
      index: index,
      store: fragments,
      locator: locator,
    ),
    writer: writer ?? FileSystemWriter.forPlatform(),
    fs: TreeWalker.defaultFileSystem(),
    selected: [for (final p in paths) _normalize(p)],
    overwrite: overwrite,
    cancel: cancel ?? CancellationToken(),
    separator: Platform.isWindows ? 0x5C : 0x2F,
  );
  target.createSync(recursive: true);
  final root = await restorer.tree(_ids(snapshot.rootTree));
  for (final node in root.nodes) {
    final original = utf8.decode(node.name, allowMalformed: true);
    final logical = _normalize(original);
    if (!restorer.wanted(logical)) continue;
    final relative = logical
        .replaceFirst(RegExp('^/+'), '')
        .replaceAll(':', '');
    var path = utf8.encode(target.absolute.path);
    for (final part in relative.split('/').where((p) => p.isNotEmpty)) {
      path = restorer.join(path, utf8.encode(part));
    }
    // Каталоги над корнем бэкапа создаются как есть, без метаданных.
    Directory.fromRawPath(path).parent.createSync(recursive: true);
    await restorer.node(node, path, logical);
  }
  restorer.result
    ..segmentsFetched = restorer.reader.segmentsFetched
    ..ownersRestored = restorer.writer.canChangeOwner;
  return restorer.result;
}

final class _Restorer {
  new({
    required this.reader,
    required this.writer,
    required this.fs,
    required this.selected,
    required this.overwrite,
    required this.cancel,
    required this.separator,
  });

  final SegmentReader reader;
  final FileSystemWriter writer;
  final FileSystemReader fs;
  final List<String> selected;
  final bool overwrite;
  final CancellationToken cancel;
  final int separator;
  final RestoreResult result = RestoreResult();

  /// Узел входит в выбор сам или ведёт к выбранному (предок).
  bool wanted(String logical) =>
      selected.isEmpty ||
      selected.any(
        (s) =>
            s == logical ||
            s.startsWith('$logical/') ||
            logical.startsWith('$s/'),
      );

  /// Выбран целиком (сам или потомок выбранного).
  bool _whole(String logical) =>
      selected.isEmpty ||
      selected.any((s) => s == logical || logical.startsWith('$s/'));

  Future<pb.Tree> tree(List<ChunkId> ids) async {
    final out = BytesBuilder(copy: false);
    for (final id in ids) {
      out.add(await reader.chunk(id));
    }
    final bytes = out.takeBytes();
    return ManifestObjects.parseMessage<pb.Tree>(
      'tree',
      () => pb.Tree.fromBuffer(bytes),
    );
  }

  Future<void> node(pb.Node node, Uint8List path, String logical) async {
    cancel.check();
    final show = utf8.decode(path, allowMalformed: true);
    try {
      switch (node.type) {
        case pb.NodeType.NODE_TYPE_DIRECTORY:
          await _directory(node, path, logical);
        case pb.NodeType.NODE_TYPE_FILE:
          if (!_whole(logical)) return;
          await _file(node, path, show);
        case pb.NodeType.NODE_TYPE_SYMLINK:
          if (!_whole(logical)) return;
          _symlink(node, path, show);
        case pb.NodeType.NODE_TYPE_UNSPECIFIED:
          result.errors.add((show, 'узел без типа'));
      }
    } on CancelledException {
      rethrow;
    } on CoreException catch (e) {
      result.errors.add((show, e.message));
    } on FileSystemException catch (e) {
      result.errors.add((show, e.osError?.message ?? e.message));
    }
  }

  Future<void> _directory(pb.Node node, Uint8List path, String logical) async {
    Directory.fromRawPath(path).createSync(recursive: true);
    final children = await tree(_ids(node.subtree));
    for (final child in children.nodes) {
      final name = utf8.decode(child.name, allowMalformed: true);
      final childLogical = '$logical/$name';
      if (!wanted(childLogical)) continue;
      await this.node(
        child,
        join(path, Uint8List.fromList(child.name)),
        childLogical,
      );
    }
    result.directories++;
    // Метаданные каталога — после содержимого: запись детей меняет mtime.
    if (_whole(logical)) _metadata(node, path, isSymlink: false);
  }

  Future<void> _file(pb.Node node, Uint8List path, String show) async {
    final existing = _kind(path);
    if (existing != null) {
      if (!overwrite) {
        result.skippedExisting.add(show);
        return;
      }
      if (existing == EntryKind.directory) {
        Directory.fromRawPath(path).deleteSync(recursive: true);
      }
    }
    final tempPath = Uint8List.fromList([
      ...path,
      ...utf8.encode('.fs-restore-tmp'),
    ]);
    final temp = File.fromRawPath(tempPath);
    final out = temp.openSync(mode: FileMode.write);
    var written = 0;
    try {
      for (final id in _ids(node.content)) {
        final data = await reader.chunk(id);
        out.writeFromSync(data);
        written += data.length;
      }
    } on Object {
      out.closeSync();
      writer.unlink(tempPath);
      rethrow;
    }
    out.closeSync();
    if (written != node.size.toInt()) {
      writer.unlink(tempPath);
      throw const IntegrityException(
        object: 'file',
        check: IntegrityCheck.hash,
      );
    }
    // rename поверх: файл или ссылка на месте заменяются атомарно.
    writer.rename(tempPath, path);
    _metadata(node, path, isSymlink: false);
    result.files++;
    result.bytes += written;
  }

  void _symlink(pb.Node node, Uint8List path, String show) {
    final existing = _kind(path);
    if (existing != null) {
      if (!overwrite) {
        result.skippedExisting.add(show);
        return;
      }
      if (existing == EntryKind.directory) {
        Directory.fromRawPath(path).deleteSync(recursive: true);
      } else {
        writer.unlink(path);
      }
    }
    writer.symlink(path, Uint8List.fromList(node.symlinkTarget));
    _metadata(node, path, isSymlink: true);
    result.symlinks++;
  }

  /// Что уже лежит по пути (без разыменования ссылок); `null` — ничего.
  EntryKind? _kind(Uint8List path) {
    try {
      return fs.stat(path, path).kind;
    } on FileSystemException {
      return null;
    }
  }

  void _metadata(pb.Node node, Uint8List path, {required bool isSymlink}) {
    if (writer.canChangeOwner) {
      writer.setOwner(path, node.uid, node.gid, isSymlink: isSymlink);
    }
    if (!isSymlink && node.mode != 0) writer.setMode(path, node.mode);
    writer.setMtime(path, node.mtimeNs.toInt(), isSymlink: isSymlink);
  }

  Uint8List join(Uint8List directory, Uint8List name) {
    final out = Uint8List(directory.length + 1 + name.length)
      ..setAll(0, directory)
      ..[directory.length] = separator
      ..setAll(directory.length + 1, name);
    return out;
  }
}

List<ChunkId> _ids(List<List<int>> raw) => [for (final r in raw) ChunkId(r)];

/// Путь из снимка в логический вид с `/` и без `/` в конце.
String _normalize(String path) {
  var p = path.replaceAll(r'\', '/');
  while (p.length > 1 && p.endsWith('/')) {
    p = p.substring(0, p.length - 1);
  }
  return p;
}
