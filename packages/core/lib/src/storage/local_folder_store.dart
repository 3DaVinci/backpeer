// FaultPlan.roll — FNV-1a на 64-битном int Dart VM; JavaScript не нужен.
// ignore_for_file: avoid_js_rounded_ints

import 'dart:io';
import 'dart:typed_data';

import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/errors.dart';
import 'package:core/src/format/fragment.dart';
import 'package:core/src/storage/fragment_store.dart';
import 'package:core/src/util/bytes.dart';

/// Внесение сбоев для тестов. Решение для каждой операции детерминировано
/// хэшем `(seed, узел, fragment_id)`, а не порядком вызовов, поэтому прогон
/// воспроизводится по [seed] и при параллельной записи.
final class FaultPlan {
  const new({
    this.seed = 0,
    this.unavailableNodes = const {},
    this.corruptReadRate = 0,
    this.failWriteRate = 0,
  });

  final int seed;

  /// Узлы, которые не отвечают.
  final Set<String> unavailableNodes;

  /// Доля чтений, в которых узел отдаёт фрагмент с одним испорченным байтом.
  final double corruptReadRate;

  /// Доля записей, падающих на середине: половина временного файла
  /// записана, фрагмент не сохранён.
  final double failWriteRate;

  static const none = FaultPlan();

  /// Число в [0, 1) для операции (FNV-1a, 64 бита; только Dart VM).
  double roll(String operation, String node, Uint8List id) {
    var h = 0xcbf29ce484222325 ^ seed;
    void mix(int b) => h = (h ^ b) * 0x100000001b3;
    operation.codeUnits.forEach(mix);
    mix(0);
    node.codeUnits.forEach(mix);
    mix(0);
    id.forEach(mix);
    return (h >>> 11) / (1 << 53);
  }
}

/// [FragmentStore] на n локальных папках: каждая изображает одного
/// хранителя (задача 1.6.1). Фрагмент — файл `<узел>/<2 hex>/<hex>.frag`;
/// запись атомарная (временный файл и переименование), недописанные
/// временные файлы после сбоя не видны и удаляются при открытии.
final class LocalFolderStore implements FragmentStore {
  new(
    this.root,
    this._crypto, {
    required int nodeCount,
    this.faults = FaultPlan.none,
  }) : nodes = List.unmodifiable([
         for (var i = 0; i < nodeCount; i++)
           'node-${i.toString().padLeft(2, '0')}',
       ]) {
    for (final node in nodes) {
      final dir = Directory('${root.path}/$node')..createSync(recursive: true);
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is File && entity.path.contains('.tmp-')) {
          entity.deleteSync();
        }
      }
    }
  }

  final Directory root;
  final CryptoProvider _crypto;
  final FaultPlan faults;

  @override
  final List<String> nodes;

  @override
  Future<Uint8List> put(
    String node,
    Uint8List fragment, {
    Uint8List? expectedFragmentId,
  }) async {
    _checkNode(node, 'put');
    final parsed = Fragment.parse(fragment)
      ..verify(_crypto, expectedFragmentId: expectedFragmentId);
    final id = parsed.header.fragmentId(_crypto);
    final file = _file(node, id);
    if (file.existsSync()) return id;
    final temp = File('${file.path}.tmp-$pid');
    try {
      file.parent.createSync(recursive: true);
      if (faults.roll('put', node, id) < faults.failWriteRate) {
        temp.writeAsBytesSync(
          Uint8List.sublistView(fragment, 0, fragment.length ~/ 2),
          flush: true,
        );
        throw StorageException(
          location: node,
          problem: StorageProblem.io,
          operation: 'put',
          cause: 'сбой записи (внесённый)',
        );
      }
      temp
        ..writeAsBytesSync(fragment, flush: true)
        ..renameSync(file.path);
    } on FileSystemException catch (e) {
      throw StorageException(
        location: node,
        problem: StorageProblem.io,
        operation: 'put',
        cause: e.osError?.message ?? e.message,
      );
    }
    return id;
  }

  @override
  Future<Uint8List> get(String node, Uint8List fragmentId) async {
    _checkNode(node, 'get');
    final file = _file(node, fragmentId);
    final Uint8List bytes;
    try {
      bytes = file.readAsBytesSync();
    } on PathNotFoundException {
      throw StorageException(
        location: '$node/${bytesToHex(fragmentId)}',
        problem: StorageProblem.notFound,
        operation: 'get',
      );
    }
    final roll = faults.roll('get', node, fragmentId);
    if (roll < faults.corruptReadRate && bytes.isNotEmpty) {
      final at = (roll / faults.corruptReadRate * bytes.length).floor();
      bytes[at.clamp(0, bytes.length - 1)] ^= 0x40;
    }
    return bytes;
  }

  @override
  Future<List<bool>> has(String node, List<Uint8List> fragmentIds) async {
    _checkNode(node, 'has');
    return [for (final id in fragmentIds) _file(node, id).existsSync()];
  }

  @override
  Future<void> delete(String node, Uint8List fragmentId) async {
    _checkNode(node, 'delete');
    final file = _file(node, fragmentId);
    if (file.existsSync()) file.deleteSync();
  }

  /// Портит сохранённый фрагмент на диске — для тестов `verify`.
  void corruptStored(String node, Uint8List fragmentId, {int offset = 200}) {
    final file = _file(node, fragmentId);
    final bytes = file.readAsBytesSync();
    bytes[offset % bytes.length] ^= 0x01;
    file.writeAsBytesSync(bytes);
  }

  File _file(String node, Uint8List id) {
    final hex = bytesToHex(id);
    return File('${root.path}/$node/${hex.substring(0, 2)}/$hex.frag');
  }

  void _checkNode(String node, String operation) {
    if (!nodes.contains(node)) {
      throw ArgumentError.value(node, 'node', 'неизвестный узел');
    }
    if (faults.unavailableNodes.contains(node)) {
      throw StorageException(
        location: node,
        problem: StorageProblem.unavailable,
        operation: operation,
      );
    }
  }
}
