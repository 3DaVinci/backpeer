import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:coordinator/src/auth/key_directory.dart';
import 'package:coordinator/src/log.dart';
import 'package:coordinator/src/nodes/node_channels.dart';
import 'package:coordinator/src/rpc/call_context.dart';
import 'package:coordinator/src/rpc/errors.dart';
import 'package:core/core.dart';
import 'package:logging/logging.dart';
import 'package:protocol/protocol.dart' as pb;

/// Настройки сведения узлов.
final class RendezvousPolicy {
  const new({
    this.publicHost,
    this.host = '0.0.0.0',
    this.port = 3478,
    this.perMinute = 30,
    this.burst = 20,
    this.ipPerSecond = 20,
    this.ipBurst = 50,
    this.tokenLifetime = const Duration(minutes: 2),
  });

  /// Адрес сводника, каким его видят узлы и клиенты (IPv4 или имя DNS);
  /// `null` — сведение выключено.
  final String? publicHost;

  /// Адрес, на котором слушает сводник.
  final String host;

  /// Первый порт сводника; второй — следующий за ним. 0 — любые
  /// свободные (тесты).
  final int port;

  /// Сведений в минуту на ключ инициатора и запас.
  final int perMinute;
  final int burst;

  /// Запросов к своднику в секунду с одного IP и запас.
  final double ipPerSecond;
  final int ipBurst;

  /// Сколько действует подтверждение адреса от сводника.
  final Duration tokenLifetime;

  bool get enabled => publicHost != null;
}

/// Подтверждения адресов сводника: `u32be` время выдачи в секундах и
/// первые 16 байт BLAKE2b-256 с ключом процесса над адресом, портом и
/// временем. Ключ новый при каждом запуске: после перезапуска старые
/// подтверждения недействительны, сторона просто спросит сводник снова.
final class RendezvousTokens {
  new(this._crypto, {SecretBytes? key, DateTime Function()? clock})
    : _key = key ?? SecretBytes(_crypto.randomBytes(32)),
      _clock = clock ?? DateTime.now;

  final CryptoProvider _crypto;
  final SecretBytes _key;
  final DateTime Function() _clock;

  static final _context = Uint8List.fromList('fs/v1/rendezvous'.codeUnits);

  Uint8List issue(InternetAddress address, int port) {
    final issued = _clock().millisecondsSinceEpoch ~/ 1000;
    return Uint8List(UdpPackets.bindingTokenLength)
      ..buffer.asByteData().setUint32(0, issued)
      ..setRange(4, 20, _mac(address, port, issued));
  }

  /// Подтверждение выдано этим процессом для [address]:[port] не раньше
  /// [lifetime] назад.
  bool verify(
    Uint8List token,
    InternetAddress address,
    int port,
    Duration lifetime,
  ) {
    if (token.length != UdpPackets.bindingTokenLength) return false;
    final issued = token.buffer.asByteData(token.offsetInBytes).getUint32(0);
    final now = _clock().millisecondsSinceEpoch ~/ 1000;
    if (issued > now + 5 || now - issued > lifetime.inSeconds) return false;
    return constantTimeEquals(
      Uint8List.sublistView(token, 4),
      _mac(address, port, issued),
    );
  }

  Uint8List _mac(InternetAddress address, int port, int issued) {
    final raw = address.rawAddress;
    final data = BytesBuilder(copy: false)
      ..add(_context)
      ..addByte(raw.length)
      ..add(raw)
      ..add([port >> 8, port & 0xff])
      ..add(Uint8List(4)..buffer.asByteData().setUint32(0, issued));
    return Uint8List.sublistView(
      _crypto.blake2b256(data.takeBytes(), key: _key),
      0,
      16,
    );
  }
}

/// Сведение узлов (задача 3.7.2; protocol.md, раздел 4.11): сводник на
/// двух портах UDP и методы `GetRendezvousInfo`, `Rendezvous`. Команду
/// узлу передаёт канал команд ([channels]).
final class RendezvousService {
  new({
    required CryptoProvider crypto,
    required this.keys,
    this.policy = const RendezvousPolicy(),
    DateTime Function()? clock,
  }) : _crypto = crypto,
       tokens = RendezvousTokens(crypto, clock: clock),
       _keyLimiter = RateLimiter(
         perSecond: policy.perMinute / 60,
         burst: policy.burst,
         clock: clock,
       ),
       _ipLimiter = RateLimiter(
         perSecond: policy.ipPerSecond,
         burst: policy.ipBurst,
         clock: clock,
       );

  final CryptoProvider _crypto;
  final KeyDirectory keys;
  final RendezvousPolicy policy;
  final RendezvousTokens tokens;
  final RateLimiter _keyLimiter;
  final RateLimiter _ipLimiter;

  /// Каналы команд; задаёт сервер после их создания.
  NodeChannels? channels;

  RendezvousServer? _server;

  static final _log = Logger('rendezvous');

  /// Порты сводника; пусто — не запущен.
  List<int> get ports => _server?.ports ?? const [];

  /// Адреса сводника для узлов и клиентов.
  List<String> get servers {
    final host = policy.publicHost;
    final server = _server;
    if (host == null || server == null) return const [];
    return [for (final p in server.ports) '$host:$p'];
  }

  /// Запускает сводник, если сведение включено.
  Future<void> start() async {
    if (!policy.enabled || _server != null) return;
    _server = await RendezvousServer.bind(
      host: policy.host,
      port: policy.port,
      issueToken: tokens.issue,
      allow: (address) => _ipLimiter.take(address.address) == null,
    );
    _log.info(LogEvent('listening', {'ports': _server!.ports}));
  }

  Future<void> close() async {
    await _server?.close();
    _server = null;
  }

  Future<pb.GetRendezvousInfoResponse> info(
    CallContext context,
    pb.GetRendezvousInfoRequest request,
  ) async => pb.GetRendezvousInfoResponse(servers: servers);

  Future<pb.RendezvousResponse> rendezvous(
    CallContext context,
    pb.RendezvousRequest request,
  ) async {
    final caller = context.caller!.publicKey;
    final nodeId = Uint8List.fromList(request.nodeId);
    if (nodeId.length != 32) throw _bad('node_id — 32 байта');
    if (constantTimeEquals(nodeId, caller)) {
      throw _bad('узел не сводится сам с собой');
    }
    final binding = parseIpEndpoint(request.binding.endpoint);
    if (binding == null) throw _bad('binding.endpoint — «IP:порт»');
    final (address, port) = binding;
    if (!tokens.verify(
      Uint8List.fromList(request.binding.token),
      address,
      port,
      policy.tokenLifetime,
    )) {
      throw _bad('binding.token не подтверждает адрес или устарел');
    }
    if (_keyLimiter.take(String.fromCharCodes(caller)) case final wait?) {
      throw RpcException(
        pb.ErrorCode.ERROR_CODE_RATE_LIMITED,
        'превышена частота сведений',
        retryAfter: wait,
      );
    }
    final hub = channels;
    if (!policy.enabled || hub == null) {
      throw const RpcException(
        pb.ErrorCode.ERROR_CODE_NOT_FOUND,
        'сведение узлов выключено',
      );
    }
    final info = await keys.lookup(nodeId);
    if (info == null ||
        info.kind != KeyKind.node ||
        info.revoked ||
        info.blocked ||
        !hub.isConnected(nodeId)) {
      throw const RpcException(
        pb.ErrorCode.ERROR_CODE_NOT_FOUND,
        'узел не найден или не на связи',
      );
    }
    final punchId = _crypto.randomBytes(UdpPackets.punchIdLength);
    final pb.NodeChannelMessage? reply;
    try {
      reply = await hub.send(
        nodeId,
        pb.CoordinatorChannelMessage(
          rendezvous: pb.RendezvousCommand(
            peerEndpoint: formatEndpoint(address, port),
            peerKey: caller,
            punchId: punchId,
            servers: servers,
          ),
        ),
      );
    } on TimeoutException {
      throw const RpcException(
        pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
        'узел не ответил на команду',
        retryAfter: Duration(seconds: 1),
      );
    }
    if (reply == null) {
      throw const RpcException(
        pb.ErrorCode.ERROR_CODE_NOT_FOUND,
        'узел не на связи',
      );
    }
    if (reply.hasError()) {
      final code = reply.error.code;
      throw RpcException(
        switch (code) {
          pb.ErrorCode.ERROR_CODE_NOT_FOUND ||
          pb.ErrorCode.ERROR_CODE_RATE_LIMITED => code,
          _ => pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
        },
        'узел: ${reply.error.message}',
        retryAfter: reply.error.retryAfterMs == 0
            ? null
            : Duration(milliseconds: reply.error.retryAfterMs),
      );
    }
    if (!reply.hasRendezvous()) {
      throw const RpcException(
        pb.ErrorCode.ERROR_CODE_INTERNAL,
        'узел ответил без адреса',
      );
    }
    final nodeBinding = reply.rendezvous.binding;
    final node = parseIpEndpoint(nodeBinding.endpoint);
    if (node == null ||
        !tokens.verify(
          Uint8List.fromList(nodeBinding.token),
          node.$1,
          node.$2,
          policy.tokenLifetime,
        )) {
      // Узел не заставит клиента слать пакеты на чужой адрес.
      throw const RpcException(
        pb.ErrorCode.ERROR_CODE_INTERNAL,
        'узел вернул неподтверждённый адрес',
      );
    }
    _log.info(
      LogEvent('rendezvous', {
        'rid': context.requestId,
        'node_id': bytesToHex(nodeId),
        'symmetric': reply.rendezvous.symmetricNat,
      }),
    );
    return pb.RendezvousResponse(
      nodeEndpoint: formatEndpoint(node.$1, node.$2),
      punchId: punchId,
      nodeSymmetricNat: reply.rendezvous.symmetricNat,
    );
  }

  static RpcException _bad(String message) =>
      RpcException(pb.ErrorCode.ERROR_CODE_BAD_REQUEST, message);
}
