// Тестовый собеседник для проверки совместимости версий протокола
// (задача 3.11.1): говорит Hello и Noise XX так же, как настоящий узел и
// клиент, но без координатора, фрагментов и хранилищ. Его запускают из
// двух разных деревьев репозитория — старая и новая сборка договариваются
// о версии, и видно, какая версия выбрана.
//
//   dart run tool/compat_peer.dart node --versions 1 [--json]
//     печатает {"listening": ПОРТ, "node_id": "…", "versions": [1]} и
//     обслуживает рукопожатия, пока процесс не остановят; на каждое
//     соединение — строка {"version": N} или {"error": "…"};
//   dart run tool/compat_peer.dart client --to АДРЕС:ПОРТ --node-id HEX
//     --versions 1,2
//     печатает {"version": N} или {"error": "…", "reason": "…"}.
//
// Версии по умолчанию — поддерживаемые этой сборкой
// (`supportedProtocolVersions`); ключ `--versions` позволяет изобразить
// другую сборку: например, новую, которая понимает версию 2, или такую,
// где общей версии нет вовсе.
//
// Сертификаты здесь самодельные: подпись проверяется ключом из самого
// сертификата, а настоящая проверка владельца идёт по талонам
// координатора, которых в этом тесте нет.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:protocol/protocol.dart' as pb;

Future<void> main(List<String> arguments) async {
  final options = _Options(List.of(arguments));
  final crypto = await SodiumCryptoProvider.load();
  final versions = _versions(options.value('--versions'));
  final json = options.flag('--json');

  switch (options.command) {
    case 'node':
      await _node(crypto, versions, json: json);
    case 'client':
      await _client(crypto, versions, options, json: json);
    default:
      stderr.writeln('peer.dart node|client …');
      exitCode = 64;
  }
}

/// Самодельная учётная запись и ключи для сертификата.
Future<LocalPeer> _identity(
  CryptoProvider crypto,
  pb.PeerRole role,
  List<int> versions,
) async {
  final account = await AccountKeys.fromMasterKey(
    SecretBytes(crypto.randomBytes(32)),
    crypto,
  );
  final issuedAt = DateTime.now().toUtc();
  if (role == pb.PeerRole.PEER_ROLE_NODE) {
    final sign = await crypto.ed25519FromSeed(
      SecretBytes(crypto.randomBytes(32)),
    );
    final dh = await crypto.x25519FromSecret(
      SecretBytes(crypto.randomBytes(32)),
    );
    final certificate = await NodeCertificates.issue(
      crypto,
      account,
      nodeId: sign.publicKey,
      nodeDh: dh.publicKey,
      issuedAt: issuedAt,
    );
    return LocalPeer(
      role: role,
      staticKey: dh,
      certificate: certificate,
      software: 'compat node',
      versions: versions,
    );
  }
  final device = await DeviceKeys.generate(crypto);
  final certificate = await DeviceCertificates.issue(
    crypto,
    account,
    device,
    issuedAt: issuedAt,
  );
  return LocalPeer(
    role: role,
    staticKey: device.dh,
    certificate: certificate,
    software: 'compat client',
    versions: versions,
  );
}

Future<void> _node(
  CryptoProvider crypto,
  List<int> versions, {
  required bool json,
}) async {
  final local = await _identity(crypto, pb.PeerRole.PEER_ROLE_NODE, versions);
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  stdout.writeln(
    jsonEncode({
      'listening': server.port,
      'node_id': _hex(local.certificate),
      'versions': versions,
    }),
  );

  await for (final socket in server) {
    unawaited(_serve(crypto, local, socket, json: json));
  }
}

/// Идентификатор узла — ключ подписи из своего сертификата.
String _hex(pb.Signed certificate) {
  final cert = pb.NodeCertificate.fromBuffer(certificate.body);
  return cert.nodeId.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

Future<void> _serve(
  CryptoProvider crypto,
  LocalPeer local,
  Socket socket, {
  required bool json,
}) async {
  final connection = SocketConnection(socket);
  try {
    final channel = await PeerHandshake.respond(
      crypto,
      connection,
      local: local,
      policy: PeerPolicy.anyone(),
    );
    _report(json: json, version: channel.peer.version);
    await channel.close();
  } on PeerRejectedException catch (e) {
    _report(json: json, error: e.toString(), reason: e.reason.name);
  } on Object catch (e) {
    _report(json: json, error: '$e');
  } finally {
    socket.destroy();
  }
}

Future<void> _client(
  CryptoProvider crypto,
  List<int> versions,
  _Options options, {
  required bool json,
}) async {
  final to = options.value('--to');
  final nodeId = options.value('--node-id');
  if (to == null || nodeId == null) {
    stderr.writeln('client: нужны --to АДРЕС:ПОРТ и --node-id HEX');
    exitCode = 64;
    return;
  }
  final colon = to.lastIndexOf(':');
  final host = to.substring(0, colon);
  final port = int.parse(to.substring(colon + 1));
  final local = await _identity(crypto, pb.PeerRole.PEER_ROLE_CLIENT, versions);

  Socket? socket;
  try {
    socket = await Socket.connect(host, port);
    final channel = await PeerHandshake.initiate(
      crypto,
      SocketConnection(socket),
      local: local,
      policy: PeerPolicy.node(Uint8List.fromList(_bytes(nodeId))),
    );
    _report(json: json, version: channel.peer.version);
    await channel.close();
  } on PeerRejectedException catch (e) {
    _report(json: json, error: e.message, reason: e.reason.name);
  } on Object catch (e) {
    _report(json: json, error: '$e');
  } finally {
    socket?.destroy();
  }
}

void _report({
  required bool json,
  int? version,
  String? error,
  String? reason,
}) {
  if (json) {
    stdout.writeln(
      jsonEncode({'version': ?version, 'error': ?error, 'reason': ?reason}),
    );
  } else if (version != null) {
    stdout.writeln('версия $version');
  } else {
    stdout.writeln('отказ: $reason ($error)');
  }
}

List<int> _versions(String? raw) {
  if (raw == null) return supportedProtocolVersions;
  return [
    for (final part in raw.split(','))
      if (part.trim().isNotEmpty) int.parse(part.trim()),
  ];
}

List<int> _bytes(String hex) => [
  for (var i = 0; i + 1 < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];

final class _Options {
  new(this._rest) {
    command = _rest.isEmpty ? '' : _rest.removeAt(0);
  }

  late final String command;
  final List<String> _rest;

  bool flag(String name) {
    final i = _rest.indexOf(name);
    if (i < 0) return false;
    _rest.removeAt(i);
    return true;
  }

  String? value(String name) {
    final i = _rest.indexOf(name);
    if (i < 0 || i + 1 >= _rest.length) return null;
    final value = _rest[i + 1];
    _rest.removeRange(i, i + 2);
    return value;
  }
}
