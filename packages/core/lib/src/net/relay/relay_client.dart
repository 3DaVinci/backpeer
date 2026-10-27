import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/src/coordinator/coordinator_client.dart';
import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/errors.dart';
import 'package:core/src/net/byte_connection.dart';
import 'package:core/src/net/relay/relay_socket.dart';
import 'package:core/src/net/relay/relay_wire.dart';
import 'package:fixnum/fixnum.dart';
import 'package:protocol/protocol.dart' as pb;

/// Relay отказал или соединение с ним не удалось.
final class RelayException implements Exception {
  const new(this.code, this.message, {this.retryAfter});

  /// `NOT_FOUND` — узла нет на relay; `UNAUTHENTICATED` — пропуск не
  /// принят; `QUOTA_EXCEEDED` — исчерпан объём пропуска;
  /// `UNAVAILABLE` — relay недоступен, перегружен или узел не ответил.
  final pb.ErrorCode code;
  final String message;
  final Duration? retryAfter;

  @override
  String toString() => 'RelayException(${code.name}: $message)';
}

/// `хост:порт` → хост и порт; IPv6 — в квадратных скобках. Неверная
/// строка — `null`.
(String, int)? splitHostPort(String endpoint) {
  final colon = endpoint.lastIndexOf(':');
  if (colon <= 0) return null;
  final port = int.tryParse(endpoint.substring(colon + 1));
  if (port == null || port < 1 || port > 65535) return null;
  var host = endpoint.substring(0, colon);
  if (host.startsWith('[')) {
    if (!host.endsWith(']')) return null;
    host = host.substring(1, host.length - 1);
  } else if (host.contains(':')) {
    return null;
  }
  return host.isEmpty ? null : (host, port);
}

/// Соединения через relay (задача 3.8.1; protocol.md, раздел 4.12) —
/// сторона клиента и узла. Пропуск выдаёт координатор (`GetRelayPass`).
abstract final class RelayClient {
  /// Ждать соединения, вызова relay и ответа на открытие.
  static const defaultTimeout = Duration(seconds: 10);

  /// Ответа на открытие CONNECT: relay ждёт соединения узла до
  /// 10 секунд.
  static const connectTimeout = Duration(seconds: 25);

  /// Соединение с узлом из пропуска CONNECT [pass]: байты дальше идут
  /// узлу как есть, поверх — Noise (`PeerHandshake.initiate`), как по TCP.
  /// Ошибки — [RelayException].
  static Future<ByteConnection> connect(
    CryptoProvider crypto, {
    required String host,
    required int port,
    required pb.Signed pass,
    required Ed25519KeyPair key,
  }) async {
    final socket = await _open(
      crypto,
      host: host,
      port: port,
      pass: pass,
      key: key,
      openTimeout: connectTimeout,
    );
    return socket.handoff();
  }

  /// Открывает соединение и проходит рукопожатие relay: вызов,
  /// доказательство владения ключом пропуска, итог.
  static Future<RelaySocket> _open(
    CryptoProvider crypto, {
    required String host,
    required int port,
    required pb.Signed pass,
    required Ed25519KeyPair key,
    List<int> accept = const [],
    Duration openTimeout = defaultTimeout,
  }) async {
    final pb.RelayPass fields;
    try {
      fields = RelayPasses.read(pass);
    } on DataFormatException catch (e) {
      throw RelayException(
        pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
        'пропуск: ${e.detail}',
      );
    }
    final Socket raw;
    try {
      raw = await Socket.connect(host, port, timeout: defaultTimeout);
    } on SocketException catch (e) {
      throw RelayException(
        pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
        'нет соединения с relay: ${e.message}',
      );
    }
    try {
      raw.setOption(SocketOption.tcpNoDelay, true);
    } on SocketException {
      // Соединение уже закрыто: увидим при чтении.
    }
    final socket = RelaySocket(raw);
    try {
      final challenge = pb.RelayChallenge.fromBuffer(
        await _frame(socket, defaultTimeout),
      );
      if (challenge.version != RelayWire.version ||
          challenge.nonce.length != RelayWire.nonceLength) {
        throw const RelayException(
          pb.ErrorCode.ERROR_CODE_VERSION_UNSUPPORTED,
          'relay другой версии',
        );
      }
      if (challenge.relay != fields.relay) {
        throw RelayException(
          pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
          'пропуск для relay ${fields.relay}, а это ${challenge.relay}',
        );
      }
      socket.send(
        pb.RelayOpen(
          pass: pass,
          proof: await RelayWire.prove(
            crypto,
            key,
            challenge.nonce,
            pass,
            accept: accept,
          ),
          accept: accept,
        ),
      );
      final opened = pb.RelayOpened.fromBuffer(
        await _frame(socket, openTimeout),
      );
      if (opened.hasError()) {
        throw RelayException(
          opened.error.code,
          opened.error.message,
          retryAfter: opened.error.retryAfterMs == 0
              ? null
              : Duration(milliseconds: opened.error.retryAfterMs),
        );
      }
      return socket;
    } on Object catch (e) {
      socket.destroy();
      if (e is RelayException) rethrow;
      throw RelayException(
        pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
        'рукопожатие с relay: $e',
      );
    }
  }

  static Future<Uint8List> _frame(RelaySocket socket, Duration timeout) async {
    final frame = await socket.next(timeout: timeout);
    if (frame == null) {
      throw const RelayException(
        pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
        'relay закрыл соединение',
      );
    }
    return frame;
  }
}

/// Управляющее соединение узла с relay по пропуску LISTEN (задача
/// 3.8.1): relay сообщает о подключениях к узлу ([incoming]), узел
/// принимает каждое новым соединением ([accept]) и передаёт его
/// `PeerService.serve`, как соединение TCP.
///
/// Живость: обе стороны шлют `ping` каждые [pingInterval]; от relay
/// ничего не пришло за два интервала — соединение закрывается
/// ([done]). Relay закрывает его сам, когда истекает пропуск: узел
/// заранее открывает новое с новым пропуском, relay заменяет им старое.
final class RelayListener {
  new _(
    this._crypto,
    this._socket,
    this.host,
    this.port,
    this.pass,
    this._key,
    this.pingInterval,
  ) : expiresAt = DateTime.fromMillisecondsSinceEpoch(
        RelayPasses.read(pass).expiresAtUnixMs.toInt(),
      ) {
    _lastSeen = DateTime.now();
    _socket.listen(_onFrame, _onClosed);
    _ping = Timer.periodic(pingInterval, (_) => _tick());
  }

  /// Открывает управляющее соединение. Ошибки — [RelayException].
  static Future<RelayListener> open(
    CryptoProvider crypto, {
    required String host,
    required int port,
    required pb.Signed pass,
    required Ed25519KeyPair key,
    Duration pingInterval = const Duration(seconds: 30),
  }) async {
    final socket = await RelayClient._open(
      crypto,
      host: host,
      port: port,
      pass: pass,
      key: key,
    );
    return RelayListener._(crypto, socket, host, port, pass, key, pingInterval);
  }

  final CryptoProvider _crypto;
  final RelaySocket _socket;
  final String host;
  final int port;
  final pb.Signed pass;
  final Ed25519KeyPair _key;
  final Duration pingInterval;

  /// Срок пропуска: к нему relay закроет соединение.
  final DateTime expiresAt;

  final _incoming = StreamController<Uint8List>();
  final _done = Completer<void>();
  late final Timer _ping;
  late DateTime _lastSeen;
  int _pings = 0;

  /// Номера сеансов: к узлу подключаются.
  Stream<Uint8List> get incoming => _incoming.stream;

  /// Завершается, когда управляющее соединение закрыто.
  Future<void> get done => _done.future;

  bool get isClosed => _done.isCompleted;

  /// Принимает сеанс [sessionId]: соединение с собеседником через relay.
  /// Ошибки — [RelayException].
  Future<ByteConnection> accept(Uint8List sessionId) async {
    final socket = await RelayClient._open(
      _crypto,
      host: host,
      port: port,
      pass: pass,
      key: _key,
      accept: sessionId,
    );
    return socket.handoff();
  }

  void close() => _socket.destroy();

  void _onFrame(Uint8List frame) {
    _lastSeen = DateTime.now();
    final pb.RelayControl message;
    try {
      message = pb.RelayControl.fromBuffer(frame);
    } on Object {
      close();
      return;
    }
    switch (message.whichBody()) {
      case pb.RelayControl_Body.incoming:
        final id = Uint8List.fromList(message.incoming.sessionId);
        if (id.length == RelayWire.sessionIdLength && !_incoming.isClosed) {
          _incoming.add(id);
        }
      case pb.RelayControl_Body.ping:
        _socket.send(pb.RelayControl(pong: message.ping));
      case pb.RelayControl_Body.pong || pb.RelayControl_Body.notSet:
        // Ответ на наш ping или незнакомое сообщение новой версии.
        break;
    }
  }

  void _tick() {
    if (DateTime.now().difference(_lastSeen) > pingInterval * 2) {
      close();
      return;
    }
    _socket.send(pb.RelayControl(ping: Int64(++_pings)));
  }

  void _onClosed() {
    _ping.cancel();
    unawaited(_incoming.close());
    if (!_done.isCompleted) _done.complete();
  }
}

/// Подключение к узлу через relay (задачи 3.8.1, 3.8.2) — сторона
/// инициатора: пропуск CONNECT у координатора (`GetRelayPass`), затем
/// соединение через relay из ответа. Поверх — Noise
/// (`PeerHandshake.initiate`), как по TCP: relay видит только шифротекст.
///
/// Ошибки: `CoordinatorException` — отказ координатора (`NOT_FOUND` —
/// узел не на relay, `QUOTA_EXCEEDED` — исчерпан объём учётной записи
/// через relay за сутки), [RelayException] — отказ relay.
final class RelayConnector {
  new({required this.client, this.key});

  final CoordinatorClient client;

  /// Ключ подписи запросов и пропуска; `null` — ключ устройства.
  final Ed25519KeyPair? key;

  Future<ByteConnection> connect(Uint8List nodeId) async {
    final signer = key ?? client.deviceKey;
    if (signer == null) throw StateError('нет ключа для пропуска relay');
    final response = await client.getRelayPass(
      pb.GetRelayPassRequest(nodeId: nodeId),
      key: key,
    );
    final endpoint = splitHostPort(response.relayEndpoint);
    if (endpoint == null) {
      throw const RelayException(
        pb.ErrorCode.ERROR_CODE_INTERNAL,
        'координатор вернул неверный адрес relay',
      );
    }
    return await RelayClient.connect(
      client.crypto,
      host: endpoint.$1,
      port: endpoint.$2,
      pass: response.pass,
      key: signer,
    );
  }
}
