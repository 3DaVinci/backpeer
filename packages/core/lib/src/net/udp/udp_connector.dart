import 'dart:io';
import 'dart:typed_data';

import 'package:core/src/coordinator/coordinator_client.dart';
import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/net/udp/udp_endpoint.dart';
import 'package:core/src/net/udp/udp_stream.dart';
import 'package:protocol/protocol.dart' as pb;

/// Подключение к узлу по UDP после сведения через координатор (задача
/// 3.7.2; protocol.md, раздел 4.11) — сторона инициатора: клиента или
/// узла при ремонте.
///
/// 1. Адреса сводника — `GetRendezvousInfo` (запоминаются).
/// 2. Внешний адрес своего сокета у сводника; симметричный NAT — отказ
///    сразу: сведение почти не удаётся, дальше — relay.
/// 3. `Rendezvous`: координатор передаёт узлу команду и возвращает его
///    внешний адрес и номер сведения.
/// 4. Пробивание NAT и поток ([UdpStream]); поверх него — Noise
///    (`PeerHandshake.initiate`), как по TCP.
///
/// Ошибки: [UdpRendezvousException] — сведение не удалось,
/// `CoordinatorException` — отказ координатора, [UdpStreamException] —
/// узел не ответил на SYN.
final class UdpConnector {
  new({
    required this.client,
    required this.endpoint,
    this.key,
    this.punchTimeout = const Duration(seconds: 15),
  });

  final CoordinatorClient client;
  final UdpEndpoint endpoint;

  /// Ключ подписи запросов; `null` — ключ устройства клиента.
  final Ed25519KeyPair? key;

  final Duration punchTimeout;

  List<(InternetAddress, int)>? _servers;

  /// Поток к узлу [nodeId].
  Future<UdpStream> connect(Uint8List nodeId) async {
    final servers = _servers ??= await _loadServers();
    if (servers.isEmpty) {
      throw const UdpRendezvousException('сведение узлов выключено');
    }
    final binding = await endpoint.discover(servers);
    if (binding.symmetric) {
      throw const UdpRendezvousException('симметричный NAT у инициатора');
    }
    final response = await client.rendezvous(
      pb.RendezvousRequest(
        nodeId: nodeId,
        binding: pb.UdpBinding(
          endpoint: binding.endpoint,
          token: binding.token,
        ),
      ),
      key: key,
    );
    if (response.nodeSymmetricNat) {
      throw const UdpRendezvousException('симметричный NAT у узла');
    }
    final node = parseIpEndpoint(response.nodeEndpoint);
    if (node == null) {
      throw const UdpRendezvousException('координатор вернул неверный адрес');
    }
    final punchId = Uint8List.fromList(response.punchId);
    final (address, port) = await endpoint.punch(
      punchId,
      node.$1,
      node.$2,
      timeout: punchTimeout,
    );
    return await endpoint.connect(address, port, punchId: punchId);
  }

  Future<List<(InternetAddress, int)>> _loadServers() async {
    final info = await client.getRendezvousInfo(key: key);
    return await resolveRendezvousServers(info.servers);
  }
}

/// Адреса сводника «хост:порт» → IPv4 и порт; имена разрешаются через
/// DNS, неразбираемые пропускаются.
Future<List<(InternetAddress, int)>> resolveRendezvousServers(
  List<String> servers,
) async {
  final out = <(InternetAddress, int)>[];
  for (final s in servers) {
    final colon = s.lastIndexOf(':');
    if (colon <= 0) continue;
    final port = int.tryParse(s.substring(colon + 1));
    if (port == null || port < 1 || port > 65535) continue;
    final host = s.substring(0, colon);
    var address = InternetAddress.tryParse(host);
    if (address == null) {
      try {
        final found = await InternetAddress.lookup(
          host,
          type: InternetAddressType.IPv4,
        );
        if (found.isEmpty) continue;
        address = found.first;
      } on SocketException {
        continue;
      }
    }
    out.add((address, port));
  }
  return out;
}
