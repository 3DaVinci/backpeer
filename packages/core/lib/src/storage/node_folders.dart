import 'dart:io';
import 'dart:typed_data';

import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/errors.dart';
import 'package:core/src/snapshot/manifest_objects.dart';
import 'package:core/src/storage/fragment_store.dart';
import 'package:core/src/storage/local_folder_store.dart';
import 'package:core/src/util/bytes.dart';
import 'package:protocol/protocol.dart' as pb;

/// Рукопожатие с узлом: имя узла в [FragmentStore] и сертификат, который
/// узел предъявляет собеседнику (в этапе 3 — по Noise, protocol.md,
/// раздел 3.2). По сертификату клиент проверяет владельцев узлов из
/// ответа координатора (раздел 5).
abstract interface class NodeDirectory {
  /// Имя узла [nodeId] в хранилище фрагментов.
  String nameOf(Uint8List nodeId);

  /// Сертификат узла (`Signed` с `NodeCertificate`); `null` — узел
  /// недоступен.
  Future<pb.Signed?> handshake(String node);
}

/// Папки-«узлы», которые изображают узлы, зарегистрированные на
/// координаторе (этап 2): папка `<root>/<node_id в hex>/` с сертификатом
/// узла `node.cert` (`fs.v1.Signed`). Фрагменты — как в
/// [LocalFolderStore]. Узел без папки или без сертификата недоступен.
final class NodeFolders implements FragmentStore, NodeDirectory {
  new(this.root, CryptoProvider crypto, {FaultPlan faults = FaultPlan.none})
    : nodes = List.unmodifiable(_scan(root)) {
    _folders = LocalFolderStore.named(root, crypto, nodes, faults: faults);
  }

  /// Файл сертификата в папке узла.
  static const certificateFile = 'node.cert';

  final Directory root;

  late final LocalFolderStore _folders;

  /// Узлы с сертификатом на момент открытия, по возрастанию имени.
  @override
  final List<String> nodes;

  static List<String> _scan(Directory root) {
    if (!root.existsSync()) return const [];
    final out = <String>[];
    for (final entity in root.listSync()) {
      if (entity is! Directory) continue;
      final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      if (RegExp(r'^[0-9a-f]{64}$').hasMatch(name) &&
          File('${entity.path}/$certificateFile').existsSync()) {
        out.add(name);
      }
    }
    return out..sort();
  }

  @override
  String nameOf(Uint8List nodeId) => bytesToHex(nodeId);

  @override
  Future<pb.Signed?> handshake(String node) async {
    if (!nodes.contains(node)) return null;
    try {
      final bytes = File('${root.path}/$node/$certificateFile')
          .readAsBytesSync();
      return ManifestObjects.parseMessage<pb.Signed>(
        certificateFile,
        () => pb.Signed.fromBuffer(bytes),
      );
    } on FileSystemException {
      return null;
    } on DataFormatException {
      return null;
    }
  }

  @override
  Future<Uint8List> put(
    String node,
    Uint8List fragment, {
    Uint8List? expectedFragmentId,
  }) async {
    _check(node, 'put');
    return await _folders.put(
      node,
      fragment,
      expectedFragmentId: expectedFragmentId,
    );
  }

  @override
  Future<Uint8List> get(String node, Uint8List fragmentId) async {
    _check(node, 'get');
    return await _folders.get(node, fragmentId);
  }

  @override
  Future<List<bool>> has(String node, List<Uint8List> fragmentIds) async {
    _check(node, 'has');
    return await _folders.has(node, fragmentIds);
  }

  @override
  Future<void> delete(String node, Uint8List fragmentId) async {
    _check(node, 'delete');
    await _folders.delete(node, fragmentId);
  }

  void _check(String node, String operation) {
    if (!nodes.contains(node)) {
      throw StorageException(
        location: node,
        problem: StorageProblem.unavailable,
        operation: operation,
        cause: 'узла нет среди папок',
      );
    }
  }
}
