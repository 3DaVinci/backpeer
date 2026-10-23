import 'dart:io';
import 'dart:typed_data';

import 'package:core/src/coordinator/coordinator_client.dart';
import 'package:core/src/crypto/certificates.dart';
import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/errors.dart';
import 'package:core/src/pipeline/garbage.dart';
import 'package:core/src/storage/local_index.dart';
import 'package:core/src/storage/node_folders.dart';
import 'package:core/src/storage/object_store.dart';
import 'package:core/src/storage/placement.dart';
import 'package:core/src/util/bytes.dart';
import 'package:fixnum/fixnum.dart';
import 'package:protocol/protocol.dart' as pb;

const pb.ErrorCode _notFound = pb.ErrorCode.ERROR_CODE_NOT_FOUND;

/// [ObjectStore] на координаторе: `PutObject`, `ListObjects`,
/// `GetObject`, `DeleteObject` (protocol.md, раздел 4.8; задача 2.8.2).
/// Ошибки координатора — [CoordinatorException]; нет объекта —
/// [StorageException] с `notFound`, как у остальных хранилищ.
final class CoordinatorObjectStore implements ObjectStore {
  new(this.client, {this.pageSize = 0});

  final CoordinatorClient client;

  /// `limit` страницы `ListObjects`; 0 — по умолчанию координатора.
  final int pageSize;

  static pb.ObjectKind _kind(ObjectKind kind) => switch (kind) {
    ObjectKind.snapshot => pb.ObjectKind.OBJECT_KIND_SNAPSHOT,
    ObjectKind.indexObject => pb.ObjectKind.OBJECT_KIND_INDEX,
  };

  @override
  Future<void> put(
    ObjectKind kind,
    Uint8List id,
    Uint8List blob, {
    int sequence = 0,
  }) async {
    await client.putObject(
      pb.PutObjectRequest(
        kind: _kind(kind),
        objectId: id,
        blob: blob,
        sequence: Int64(sequence),
      ),
    );
  }

  @override
  Future<List<ObjectInfo>> list(ObjectKind kind) async {
    final out = <ObjectInfo>[];
    var after = Uint8List(0);
    for (;;) {
      final page = await client.listObjects(
        pb.ListObjectsRequest(
          kind: _kind(kind),
          afterObjectId: after,
          limit: pageSize,
        ),
      );
      for (final o in page.objects) {
        final id = Uint8List.fromList(o.objectId);
        // Порядок и отсутствие повторов — чтобы подменённый ответ не
        // зациклил обход страниц.
        if (out.isNotEmpty && _compare(out.last.id, id) >= 0) {
          throw const CoordinatorException(
            pb.ErrorCode.ERROR_CODE_INTERNAL,
            'ListObjects: объекты не по возрастанию',
          );
        }
        out.add(
          ObjectInfo(
            id: id,
            size: o.size,
            storedAtMs: o.storedAtUnixMs.toInt(),
            sequence: o.sequence.toInt(),
          ),
        );
      }
      if (!page.more) return out;
      if (page.objects.isEmpty) {
        throw const CoordinatorException(
          pb.ErrorCode.ERROR_CODE_INTERNAL,
          'ListObjects: пустая страница с more',
        );
      }
      after = out.last.id;
    }
  }

  @override
  Future<Uint8List> get(ObjectKind kind, Uint8List id) async {
    try {
      final r = await client.getObject(
        pb.GetObjectRequest(kind: _kind(kind), objectId: id),
      );
      return Uint8List.fromList(r.blob);
    } on CoordinatorException catch (e) {
      if (e.code != _notFound) rethrow;
      throw StorageException(
        location: 'координатор, объект ${bytesToHex(id)}',
        problem: StorageProblem.notFound,
        operation: 'get',
      );
    }
  }

  @override
  Future<void> delete(ObjectKind kind, Uint8List id) async {
    await client.deleteObject(
      pb.DeleteObjectRequest(kind: _kind(kind), objectId: id),
    );
  }
}

/// Узел из ответа координатора, как его видит клиент.
final class PlacedNode {
  const new({
    required this.nodeId,
    required this.owner,
    this.endpoints = const [],
  });

  final Uint8List nodeId;

  /// `account_id` из сертификата узла, полученного в рукопожатии.
  final Uint8List owner;

  /// Адреса, к которым клиент подключается.
  final List<String> endpoints;
}

/// Проверка размещения клиентом (protocol.md, раздел 5; угроза К-5):
/// узлы различны, их владельцы различны и не совпадают с учётной записью
/// клиента, подсети адресов (IPv4 /24, IPv6 /48) не повторяются. Узлы
/// без адреса (за NAT, через relay) по подсети не проверяются: клиент её
/// не видит.
abstract final class PlacementCheck {
  /// Описание нарушения или `null`.
  static String? problem(List<PlacedNode> nodes, {Uint8List? ownAccount}) {
    final ids = <String>{};
    final owners = <String>{};
    final subnets = <String>{};
    for (final node in nodes) {
      if (!ids.add(bytesToHex(node.nodeId))) return 'узел повторяется';
      if (ownAccount != null && constantTimeEquals(node.owner, ownAccount)) {
        return 'узел принадлежит владельцу сегмента';
      }
      if (!owners.add(bytesToHex(node.owner))) return 'владелец повторяется';
      for (final subnet in {for (final e in node.endpoints) ?subnetOf(e)}) {
        if (!subnets.add(subnet)) return 'подсеть $subnet повторяется';
      }
    }
    return null;
  }

  /// Подсеть адреса `хост:порт` или `[IPv6]:порт`; имя DNS и неразбираемый
  /// адрес — `null`.
  static String? subnetOf(String endpoint) {
    final colon = endpoint.lastIndexOf(':');
    if (colon <= 0) return null;
    var host = endpoint.substring(0, colon);
    if (host.startsWith('[') && host.endsWith(']')) {
      host = host.substring(1, host.length - 1);
    }
    final address = InternetAddress.tryParse(host);
    if (address == null) return null;
    final raw = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      return '${raw[0]}.${raw[1]}.${raw[2]}.0/24';
    }
    // IPv4, отображённый в IPv6 (::ffff:a.b.c.d), — как IPv4.
    final mapped =
        raw.sublist(0, 10).every((b) => b == 0) &&
        raw[10] == 0xFF &&
        raw[11] == 0xFF;
    if (mapped) return '${raw[12]}.${raw[13]}.${raw[14]}.0/24';
    return '${bytesToHex(raw.sublist(0, 6))}/48';
  }
}

/// Сегменты через координатор (задача 2.8.2; protocol.md, раздел 5.2):
/// размещение `AllocateSegment` с проверкой клиентом, подтверждение
/// `CommitSegment`, поиск фрагментов `LocateSegment`, освобождение
/// `DeleteSegment` при сборке мусора.
///
/// Владельцев узлов клиент узнаёт из сертификатов, которые узлы
/// предъявляют в рукопожатии ([NodeDirectory]); узел, с которым
/// рукопожатие не удалось, фрагмент не получает (он считается
/// незагруженным). Размещение с нарушением отклоняется и запрашивается
/// заново; повторное нарушение — [PlacementRejectedException].
final class CoordinatorSegments
    implements SegmentPlacer, SegmentLocator, SegmentReleaser {
  new({
    required this.client,
    required this.crypto,
    required this.nodes,
    required this.accountId,
    this.fallbackReleaser,
  });

  final CoordinatorClient client;
  final CryptoProvider crypto;
  final NodeDirectory nodes;

  /// Учётная запись клиента: её узлы не должны хранить её сегменты.
  final Uint8List accountId;

  /// Освобождение сегмента, которого координатор уже не знает (повтор
  /// после обрыва): фрагменты ищутся по локальному индексу.
  final SegmentReleaser? fallbackReleaser;

  /// Сколько раз размещение отклонялось — для журнала и тестов.
  int rejectedPlacements = 0;

  @override
  Future<List<FragmentTarget?>> allocate(SegmentAllocation segment) async {
    final request = pb.AllocateSegmentRequest(
      segmentId: segment.segmentId,
      k: segment.k,
      n: segment.n,
      repairThreshold: segment.repairThreshold,
      fragmentSize: segment.fragmentSize,
      fragmentIds: segment.fragmentIds,
      bodyRoots: segment.bodyRoots,
    );
    for (var attempt = 1; ; attempt++) {
      final response = await client.allocateSegment(request);
      final (targets, problem) = await _check(response, segment.n);
      if (problem == null) return targets;
      rejectedPlacements++;
      if (attempt >= 2) {
        throw PlacementRejectedException(problem, segmentId: segment.segmentId);
      }
    }
  }

  /// Цели по номерам фрагментов и нарушение, если есть.
  Future<(List<FragmentTarget?>, String?)> _check(
    pb.AllocateSegmentResponse response,
    int n,
  ) async {
    final placements = response.placements;
    if (placements.length != n) {
      return (
        const <FragmentTarget?>[],
        'узлов ${placements.length}, нужно $n',
      );
    }
    final targets = List<FragmentTarget?>.filled(n, null);
    final placed = <PlacedNode>[];
    for (var i = 0; i < n; i++) {
      final p = placements[i];
      if (p.index != i || p.node.nodeId.length != CryptoProvider.keyLength) {
        return (const <FragmentTarget?>[], 'неверная запись размещения $i');
      }
      final nodeId = Uint8List.fromList(p.node.nodeId);
      final name = nodes.nameOf(nodeId);
      final owner = await _owner(name, nodeId);
      if (owner == null) continue;
      placed.add(
        PlacedNode(nodeId: nodeId, owner: owner, endpoints: p.node.endpoints),
      );
      targets[i] = FragmentTarget(index: i, node: name, ticket: p.ticket);
    }
    return (targets, PlacementCheck.problem(placed, ownAccount: accountId));
  }

  /// Владелец узла по сертификату из рукопожатия; узел недоступен или
  /// сертификат не сходится — `null`.
  Future<Uint8List?> _owner(String name, Uint8List nodeId) async {
    final signed = await nodes.handshake(name);
    if (signed == null) return null;
    try {
      final cert = await NodeCertificates.open(crypto, signed, nodeId: nodeId);
      return Uint8List.fromList(cert.accountId);
    } on CoreException {
      return null;
    }
  }

  @override
  Future<void> commit(Uint8List segmentId, List<int> storedIndexes) async {
    await client.commitSegment(
      pb.CommitSegmentRequest(
        segmentId: segmentId,
        storedIndexes: storedIndexes,
      ),
    );
  }

  @override
  Future<Map<int, String>> locate(Uint8List segmentId) async {
    final pb.LocateSegmentResponse response;
    try {
      response = await client.locateSegment(
        pb.LocateSegmentRequest(segmentId: segmentId),
      );
    } on CoordinatorException catch (e) {
      if (e.code == _notFound) return const {};
      rethrow;
    }
    return {
      for (final p in response.placements)
        if (p.node.nodeId.length == CryptoProvider.keyLength)
          p.index: nodes.nameOf(Uint8List.fromList(p.node.nodeId)),
    };
  }

  @override
  Future<List<FragmentLocation>> release(SegmentEntry segment) async {
    final pb.DeleteSegmentResponse response;
    try {
      response = await client.deleteSegment(
        pb.DeleteSegmentRequest(segmentId: segment.segmentId),
      );
    } on CoordinatorException catch (e) {
      final fallback = fallbackReleaser;
      if (e.code != _notFound || fallback == null) rethrow;
      return await fallback.release(segment);
    }
    final ids = {for (final f in segment.fragmentIds.indexed) f.$1: f.$2};
    return [
      for (final p in response.placements)
        if (ids[p.index] case final Uint8List fragmentId
            when p.node.nodeId.length == CryptoProvider.keyLength)
          (
            node: nodes.nameOf(Uint8List.fromList(p.node.nodeId)),
            fragmentId: fragmentId,
          ),
    ];
  }
}

int _compare(Uint8List a, Uint8List b) {
  for (var i = 0; i < a.length && i < b.length; i++) {
    if (a[i] != b[i]) return a[i] - b[i];
  }
  return a.length - b.length;
}
