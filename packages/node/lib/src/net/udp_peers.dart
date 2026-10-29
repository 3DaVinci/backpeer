import 'dart:async';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:daemon_kit/daemon_kit.dart';
import 'package:logging/logging.dart';
import 'package:protocol/protocol.dart' as pb;

/// Приём соединений по UDP после сведения через координатор (задачи
/// 3.7.2–3.7.4; protocol.md, раздел 4.11): сокет UDP узла, команда
/// `RendezvousCommand` и потоки, которые передаются [serve] — тому же
/// `PeerService.serve`, что у TCP.
///
/// По команде узел узнаёт свой внешний адрес у сводника, отвечает им
/// координатору и, если NAT не симметричный, [punchTimeout] пробивает его
/// к инициатору в фоне; SYN с номером этого сведения принимается.
final class UdpPeers {
  new _(this.endpoint, this.serve, this.punchTimeout) {
    _subscription = endpoint.incoming.listen((stream) {
      unawaited(_serve(stream));
    });
  }

  /// Привязывает сокет UDP к [port] (0 — любой свободный) на всех адресах
  /// IPv4.
  static Future<UdpPeers> bind(
    int port,
    Future<void> Function(ByteConnection connection) serve, {
    Duration punchTimeout = const Duration(seconds: 15),
    UdpStreamOptions options = const UdpStreamOptions(),
  }) async => UdpPeers._(
    await UdpEndpoint.bind(port: port, options: options),
    serve,
    punchTimeout,
  );

  final UdpEndpoint endpoint;
  final Future<void> Function(ByteConnection connection) serve;
  final Duration punchTimeout;
  late final StreamSubscription<UdpStream> _subscription;
  final _active = <Future<void>>{};

  int rendezvous = 0;
  String? lastError;
  bool? symmetricNat;

  static final _log = Logger('udp');

  int get port => endpoint.port;

  Map<String, Object?> toJson() => {
    ...endpoint.toJson(),
    'rendezvous': rendezvous,
    'symmetricNat': symmetricNat,
    'lastError': lastError,
  };

  /// Выполняет команду сведения; ошибка — [CoordinatorException] для
  /// ответа координатору.
  Future<pb.RendezvousReply> handle(pb.RendezvousCommand command) async {
    final peer = parseIpEndpoint(command.peerEndpoint);
    if (peer == null || command.punchId.length != UdpPackets.punchIdLength) {
      throw const CoordinatorException(
        pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
        'неверная команда сведения',
      );
    }
    final servers = await resolveRendezvousServers(command.servers);
    if (servers.isEmpty) {
      throw const CoordinatorException(
        pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
        'нет адресов сводника',
      );
    }
    rendezvous++;
    final UdpBinding binding;
    try {
      binding = await endpoint.discover(servers);
    } on UdpRendezvousException catch (e) {
      lastError = e.message;
      throw CoordinatorException(
        pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
        e.message,
        retryAfter: const Duration(seconds: 5),
      );
    }
    symmetricNat = binding.symmetric;
    if (!binding.symmetric) {
      final punchId = Uint8List.fromList(command.punchId);
      unawaited(
        endpoint
            .punch(punchId, peer.$1, peer.$2, timeout: punchTimeout)
            .then(
              (_) => _log.fine(const LogEvent('punch_ok')),
              onError: (Object e) {
                lastError = '$e';
                _log.info(LogEvent('punch_failed', {'reason': '$e'}));
              },
            ),
      );
    }
    _log.info(
      LogEvent('rendezvous', {
        'symmetric': binding.symmetric,
        'peer_key': bytesToHex(command.peerKey),
      }),
    );
    return pb.RendezvousReply(
      binding: pb.UdpBinding(endpoint: binding.endpoint, token: binding.token),
      symmetricNat: binding.symmetric,
    );
  }

  Future<void> _serve(UdpStream stream) async {
    final served = serve(stream);
    _active.add(served);
    try {
      await served;
    } on Object catch (e) {
      _log.fine(const LogEvent('udp_peer_error'), e);
    } finally {
      _active.remove(served);
    }
  }

  Future<void> close() async {
    await _subscription.cancel();
    await endpoint.close();
    await Future.wait(_active.toList());
  }
}
