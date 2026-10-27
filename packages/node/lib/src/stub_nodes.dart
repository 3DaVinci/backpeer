import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:protocol/protocol.dart' as pb;

/// Узлы-заглушки этапа 2: папки, которые координатор считает
/// зарегистрированными узлами, а клиент пишет в них фрагменты как в
/// [NodeFolders]. Сети нет — она появится в этапе 3.
///
/// Каждый узел — папка `<root>/<node_id в hex>/` с сертификатом
/// `node.cert` и закрытыми ключами `node.key` (seed Ed25519 и ключ X25519,
/// права 0600). У каждого узла свой владелец — отдельная учётная запись
/// без копии мастер-ключа: размещение требует разных владельцев. Только
/// для разработки и тестов.
final class StubNodes {
  new({required this.root, required this.client, required this.crypto});

  static const keyFile = 'node.key';

  final Directory root;
  final CoordinatorClient client;
  final CryptoProvider crypto;

  /// Регистрирует [count] новых узлов ёмкостью [capacityBytes]; возвращает
  /// их `node_id`.
  Future<List<Uint8List>> create(
    int count, {
    int capacityBytes = 1 << 40,
  }) async {
    root.createSync(recursive: true);
    final out = <Uint8List>[];
    for (var i = 0; i < count; i++) {
      final node = await DeviceKeys.generate(crypto);
      try {
        final cert = await issueStandCertificate(
          client,
          crypto,
          nodeId: node.sign.publicKey,
          nodeDh: node.dh.publicKey,
          loginPrefix: 'stub',
        );
        await _register(node, cert, capacityBytes);
        final dir = Directory('${root.path}/${bytesToHex(node.deviceId)}')
          ..createSync();
        final secret = node.toSecret();
        try {
          writePrivateFileAtomic(File('${dir.path}/$keyFile'), secret.bytes);
        } finally {
          secret.dispose();
        }
        File('${dir.path}/${NodeFolders.certificateFile}')
            .writeAsBytesSync(cert.writeToBuffer(), flush: true);
        out.add(node.deviceId);
      } finally {
        node.dispose();
      }
    }
    return out;
  }

  /// Heartbeat всех узлов: занятое место — размер папки. Возвращает
  /// интервал до следующего, который назвал координатор.
  Future<Duration> heartbeat({int capacityBytes = 1 << 40}) async {
    var next = const Duration(minutes: 5);
    for (final (dir, node) in await _nodes()) {
      try {
        final response = await client.heartbeat(
          pb.HeartbeatRequest(
            usedBytes: Int64(_size(dir)),
            capacityBytes: Int64(capacityBytes),
          ),
          nodeKey: node.sign,
        );
        if (response.nextHeartbeatMs > 0) {
          next = Duration(milliseconds: response.nextHeartbeatMs);
        }
      } finally {
        node.dispose();
      }
    }
    return next;
  }

  /// Ключи узлов из папок.
  Future<List<(Directory, DeviceKeys)>> _nodes() async {
    if (!root.existsSync()) return const [];
    final out = <(Directory, DeviceKeys)>[];
    for (final entity
        in root.listSync()..sort((a, b) => a.path.compareTo(b.path))) {
      final key = File('${entity.path}/$keyFile');
      if (entity is! Directory || !key.existsSync()) continue;
      final secret = SecretBytes(key.readAsBytesSync());
      try {
        out.add((entity, await DeviceKeys.fromSecret(crypto, secret)));
      } finally {
        secret.dispose();
      }
    }
    return out;
  }

  /// Сертификат узла [nodeId] от нового владельца: случайная учётная
  /// запись без копии мастер-ключа, зарегистрированная на координаторе под
  /// именем `<loginPrefix>-<начало account_id>`. Мастер-ключ нигде не
  /// сохраняется — у такого узла нет владельца-человека. Только для
  /// стендов: узлы-заглушки и `node stand-cert` в Docker-образе узла.
  static Future<pb.Signed> issueStandCertificate(
    CoordinatorClient client,
    CryptoProvider crypto, {
    required Uint8List nodeId,
    required Uint8List nodeDh,
    required String loginPrefix,
  }) async {
    final owner = await AccountKeys.fromMasterKey(
      SecretBytes(crypto.randomBytes(32)),
      crypto,
    );
    final ownerDevice = await DeviceKeys.generate(crypto);
    try {
      final now = DateTime.now();
      await client.registerAccount(
        pb.RegisterAccountRequest(
          deviceCertificate: await DeviceCertificates.issue(
            crypto,
            owner,
            ownerDevice,
            issuedAt: now,
          ),
          login: '$loginPrefix-${bytesToHex(owner.accountId).substring(0, 16)}',
        ),
        accountKey: owner.accountSign,
      );
      return await NodeCertificates.issue(
        crypto,
        owner,
        nodeId: nodeId,
        nodeDh: nodeDh,
        issuedAt: now,
      );
    } finally {
      owner.dispose();
      ownerDevice.dispose();
    }
  }

  Future<void> _register(DeviceKeys node, pb.Signed cert, int capacity) =>
      client.registerNode(
        pb.RegisterNodeRequest(
          nodeCertificate: cert,
          capacityBytes: Int64(capacity),
          versions: const [1],
          software: 'node-stub $appVersion',
        ),
        nodeKey: node.sign,
      );

  static int _size(Directory dir) {
    var total = 0;
    for (final f in dir.listSync(recursive: true)) {
      if (f is File) total += f.lengthSync();
    }
    return total;
  }
}
