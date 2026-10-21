import 'dart:io';
import 'dart:typed_data';

import 'package:core/src/errors.dart';
import 'package:core/src/storage/object_store.dart';
import 'package:core/src/util/bytes.dart';

/// [ObjectStore] в локальной папке — заглушка координатора для этапа 1.
/// Объект — файл `<вид>/<hex id>.<sequence>.blob`; запись атомарная
/// (временный файл и переименование).
final class LocalObjectStore implements ObjectStore {
  new(this.root);

  final Directory root;

  @override
  Future<void> put(
    ObjectKind kind,
    Uint8List id,
    Uint8List blob, {
    int sequence = 0,
  }) async {
    _checkId(id);
    RangeError.checkNotNegative(sequence, 'sequence');
    final dir = _dir(kind);
    await _guard(dir.path, 'put', () async {
      await dir.create(recursive: true);
      await _remove(kind, id);
      final target = File('${dir.path}/${bytesToHex(id)}.$sequence.blob');
      final temp = File('${target.path}.tmp-$pid');
      await temp.writeAsBytes(blob, flush: true);
      await temp.rename(target.path);
    });
  }

  @override
  Future<List<ObjectInfo>> list(ObjectKind kind) async {
    final dir = _dir(kind);
    return await _guard(dir.path, 'list', () async {
      if (!dir.existsSync()) return const <ObjectInfo>[];
      final out = <ObjectInfo>[];
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final parsed = _parseName(entity.uri.pathSegments.last);
        if (parsed == null) continue;
        final stat = entity.statSync();
        out.add(
          ObjectInfo(
            id: parsed.id,
            size: stat.size,
            storedAtMs: stat.modified.millisecondsSinceEpoch,
            sequence: parsed.sequence,
          ),
        );
      }
      out.sort((a, b) => bytesToHex(a.id).compareTo(bytesToHex(b.id)));
      return out;
    });
  }

  @override
  Future<Uint8List> get(ObjectKind kind, Uint8List id) async {
    _checkId(id);
    final file = _find(kind, id);
    if (file == null) {
      throw StorageException(
        location: '${_dir(kind).path}/${bytesToHex(id)}',
        problem: StorageProblem.notFound,
        operation: 'get',
      );
    }
    return await _guard(file.path, 'get', file.readAsBytes);
  }

  @override
  Future<void> delete(ObjectKind kind, Uint8List id) async {
    _checkId(id);
    await _guard(_dir(kind).path, 'delete', () => _remove(kind, id));
  }

  Directory _dir(ObjectKind kind) => Directory(
    '${root.path}/${kind == ObjectKind.snapshot ? 'snapshot' : 'index'}',
  );

  File? _find(ObjectKind kind, Uint8List id) {
    final dir = _dir(kind);
    if (!dir.existsSync()) return null;
    final prefix = '${bytesToHex(id)}.';
    for (final entity in dir.listSync()) {
      if (entity is File &&
          entity.uri.pathSegments.last.startsWith(prefix) &&
          entity.path.endsWith('.blob')) {
        return entity;
      }
    }
    return null;
  }

  Future<void> _remove(ObjectKind kind, Uint8List id) async {
    await _find(kind, id)?.delete();
  }

  static ({Uint8List id, int sequence})? _parseName(String name) {
    final parts = name.split('.');
    if (parts.length != 3 || parts[2] != 'blob' || parts[0].length != 64) {
      return null;
    }
    final sequence = int.tryParse(parts[1]);
    if (sequence == null) return null;
    try {
      return (id: hexToBytes(parts[0]), sequence: sequence);
    } on FormatException {
      return null;
    }
  }

  static void _checkId(Uint8List id) {
    if (id.length != 32) {
      throw ArgumentError('Идентификатор объекта — 32 байта');
    }
  }

  static Future<T> _guard<T>(
    String location,
    String operation,
    Future<T> Function() body,
  ) async {
    try {
      return await body();
    } on FileSystemException catch (e) {
      throw StorageException(
        location: location,
        problem: StorageProblem.io,
        operation: operation,
        cause: e.osError?.message ?? e.message,
      );
    }
  }
}
