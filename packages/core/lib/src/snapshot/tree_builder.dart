import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/src/chunking/chunk_id.dart';
import 'package:core/src/chunking/fastcdc.dart';
import 'package:core/src/chunking/file_chunker.dart';
import 'package:core/src/errors.dart';
import 'package:core/src/format/segment.dart';
import 'package:core/src/snapshot/chunk_sink.dart';
import 'package:core/src/snapshot/fs_entry.dart';
import 'package:core/src/snapshot/walker.dart';
import 'package:core/src/storage/local_index.dart';
import 'package:fixnum/fixnum.dart';
import 'package:protocol/protocol.dart' as pb;

/// Счётчики построения снимка; входят в `SnapshotStats`.
final class TreeStats {
  int files = 0;
  int directories = 0;
  int bytes = 0;
  int newChunks = 0;
  int newBytes = 0;

  /// Пропущено из-за ошибок и особых файлов (по отчёту обхода).
  int skipped = 0;

  /// Файлов прочитано с диска (остальные взяты из кеша файлов).
  int filesRead = 0;

  /// Байт прочитано с диска — для прогресса.
  int bytesRead = 0;

  pb.SnapshotStats toProto() => pb.SnapshotStats(
    files: Int64(files),
    directories: Int64(directories),
    bytes: Int64(bytes),
    newChunks: Int64(newChunks),
    newBytes: Int64(newBytes),
    skipped: Int64(skipped),
  );
}

/// Строит деревья каталогов снимка (manifest.md, разделы 2–3): обходит
/// папки, режет изменённые файлы на чанки, сериализует `Tree` каждого
/// каталога, режет его FastCDC и отдаёт как чанки типа 2.
///
/// Инкрементальность: файл с тем же размером, временем и inode, что в кеше
/// файлов [index], и все чанки которого известны [sink], не читается.
/// Неизменённый каталог даёт те же байты `Tree`, значит тот же chunk_id, и
/// повторно не сохраняется.
final class TreeBuilder {
  new({
    required this.walker,
    required this.cdc,
    required this.hasher,
    required this.sink,
    required this.index,
  });

  final TreeWalker walker;
  final FastCdc cdc;
  final ChunkIdHasher hasher;
  final ChunkSink sink;
  final LocalIndex index;
  final TreeStats stats = TreeStats();

  /// Корневое дерево снимка: по узлу на каждый путь из [paths], имя узла —
  /// путь целиком в UTF-8 (manifest.md, раздел 2). Возвращает chunk_id
  /// чанков корневого дерева.
  Future<List<ChunkId>> buildRoot(List<String> paths) async {
    final nodes = <pb.Node>[];
    for (final path in paths) {
      final raw = TreeWalker.rootPath(path);
      final FsEntry entry;
      try {
        entry = walker.root(raw);
      } on FileSystemException catch (e) {
        walker.report.skipped.add(
          SkippedEntry(path, SkipReason.error, e.osError?.message ?? e.message),
        );
        continue;
      }
      final node = await _node(raw, '', entry, name: raw);
      if (node != null) nodes.add(node);
    }
    nodes.sort((a, b) => compareBytes(_bytes(a.name), _bytes(b.name)));
    final root = await _storeTree(nodes);
    stats.skipped = walker.report.skipped.length;
    return root;
  }

  /// Дерево каталога [path]; [relative] — путь от корня бэкапа.
  Future<List<ChunkId>> buildDirectory(Uint8List path, String relative) async {
    final nodes = <pb.Node>[];
    for (final entry in walker.list(path, relative)) {
      final child = walker.join(path, entry.name);
      final rel = relative.isEmpty
          ? _show(entry.name)
          : '$relative/${_show(entry.name)}';
      final node = await _node(child, rel, entry);
      if (node != null) nodes.add(node);
    }
    return await _storeTree(nodes);
  }

  Future<pb.Node?> _node(
    Uint8List path,
    String relative,
    FsEntry entry, {
    Uint8List? name,
  }) async {
    final node = pb.Node(
      name: name ?? entry.name,
      mtimeNs: Int64(entry.mtimeNs),
      mode: entry.mode,
      uid: entry.uid,
      gid: entry.gid,
      windowsAttributes: entry.windowsAttributes,
    );
    switch (entry.kind) {
      case EntryKind.file:
        final content = await _fileContent(path, entry);
        if (content == null) return null;
        stats.files++;
        stats.bytes += content.size;
        return node
          ..type = pb.NodeType.NODE_TYPE_FILE
          ..size = Int64(content.size)
          ..content.addAll(content.chunks.map((c) => c.bytes));
      case EntryKind.directory:
        stats.directories++;
        final subtree = await buildDirectory(path, relative);
        return node
          ..type = pb.NodeType.NODE_TYPE_DIRECTORY
          ..subtree.addAll(subtree.map((c) => c.bytes));
      case EntryKind.symlink:
        final target = walker.readLink(path);
        if (target == null) return null;
        return node
          ..type = pb.NodeType.NODE_TYPE_SYMLINK
          ..symlinkTarget = target;
      case EntryKind.other:
        return null;
    }
  }

  Future<({List<ChunkId> chunks, int size})?> _fileContent(
    Uint8List path,
    FsEntry entry,
  ) async {
    // Пустой файл открывать незачем; если он вырос после обхода, следующий
    // бэкап увидит другой штамп.
    if (entry.size == 0) return (chunks: const <ChunkId>[], size: 0);
    final stamp = FileStamp.fromEntry(entry);
    final cached = index.cachedFile(path, stamp);
    if (cached != null && cached.every(sink.contains)) {
      return (chunks: cached, size: entry.size);
    }
    stats.filesRead++;
    var chunks = <ChunkId>[];
    var size = 0;
    try {
      final events = chunkFile(
        File.fromRawPath(path),
        cdc,
        stamp: () {
          final now = walker.fs.stat(path, entry.name);
          return (size: now.size, mtimeNs: now.mtimeNs, ctimeNs: now.ctimeNs);
        },
      );
      await for (final event in events) {
        switch (event) {
          case ChunkRead(:final data):
            final id = hasher.of(data);
            if (await sink.add(id, ChunkType.file, data)) {
              stats.newChunks++;
              stats.newBytes += data.length;
            }
            chunks.add(id);
            size += data.length;
            stats.bytesRead += data.length;
          case ReadRestarted():
            chunks = <ChunkId>[];
            size = 0;
        }
      }
    } on SourceChangedException catch (e) {
      _skip(path, e.message);
      return null;
    } on FileSystemException catch (e) {
      _skip(path, e.osError?.message ?? e.message);
      return null;
    }
    // Штамп снят до чтения: если файл менялся после обхода, следующий
    // бэкап увидит другой штамп и прочитает файл снова.
    index.putFile(path, stamp, chunks);
    return (chunks: chunks, size: size);
  }

  Future<List<ChunkId>> _storeTree(List<pb.Node> nodes) async {
    final bytes = pb.Tree(nodes: nodes).writeToBuffer();
    final ids = <ChunkId>[];
    var offset = 0;
    for (final length in cdc.chunkLengths(bytes)) {
      final data = Uint8List.sublistView(bytes, offset, offset + length);
      offset += length;
      final id = hasher.of(data);
      if (await sink.add(id, ChunkType.tree, data)) {
        stats.newChunks++;
        stats.newBytes += data.length;
      }
      ids.add(id);
    }
    return ids;
  }

  void _skip(Uint8List path, String detail) {
    walker.report.skipped.add(
      SkippedEntry(_show(path), SkipReason.error, detail),
    );
  }

  static String _show(Uint8List bytes) =>
      utf8.decode(bytes, allowMalformed: true);

  static Uint8List _bytes(List<int> list) =>
      list is Uint8List ? list : Uint8List.fromList(list);
}
