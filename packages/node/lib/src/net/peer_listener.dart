import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';
import 'package:logging/logging.dart';
import 'package:node/src/daemon/log.dart';

/// Приём входящих TCP-соединений собеседников (задача 3.5.1): каждое
/// соединение уходит обработчику `onConnection` (`PeerService.serve`),
/// который проводит рукопожатие Noise и проверяет пределы.
///
/// Адрес по умолчанию — все адреса IPv6 и IPv4 одним сокетом; где IPv6
/// выключен, — все адреса IPv4.
final class PeerListener {
  new _(this._server, this._onConnection);

  static final _log = Logger('listen');

  /// Открывает порт [port] на [host] (`null` — все адреса); порт 0 —
  /// любой свободный (тесты). Порт занят — [SocketException].
  static Future<PeerListener> bind(
    String? host,
    int port,
    Future<void> Function(ByteConnection connection) onConnection,
  ) async {
    final ServerSocket server;
    if (host != null) {
      server = await ServerSocket.bind(host, port);
    } else {
      try {
        server = await ServerSocket.bind(InternetAddress.anyIPv6, port);
      } on SocketException catch (e) {
        // Порт занят — та же ошибка и для IPv4.
        if (_addressInUse(e)) rethrow;
        _log.fine(LogEvent('listen_ipv6_unavailable', {'error': e.message}));
        return PeerListener._(
          await ServerSocket.bind(InternetAddress.anyIPv4, port),
          onConnection,
        ).._start();
      }
    }
    return PeerListener._(server, onConnection).._start();
  }

  final ServerSocket _server;
  final Future<void> Function(ByteConnection connection) _onConnection;
  StreamSubscription<Socket>? _subscription;

  /// Принятых соединений с запуска.
  int accepted = 0;

  /// Порт, на котором узел принимает соединения.
  int get port => _server.port;

  InternetAddress get address => _server.address;

  void _start() {
    _subscription = _server.listen(
      (socket) {
        accepted++;
        try {
          socket.setOption(SocketOption.tcpNoDelay, true);
        } on SocketException {
          // Соединение уже закрыто: обработчик это увидит.
        }
        unawaited(_onConnection(SocketConnection(socket)));
      },
      onError: (Object e) {
        // Например, исчерпаны дескрипторы: приём продолжается.
        _log.warning(LogEvent('accept_failed', {'error': '$e'}));
      },
    );
    _log.info(
      LogEvent('listening', {'address': _server.address.address, 'port': port}),
    );
  }

  /// Перестаёт принимать новые соединения; принятые не трогает.
  Future<void> close() async {
    await _subscription?.cancel();
    await _server.close();
  }

  Map<String, Object?> toJson() => {
    'address': _server.address.address,
    'port': port,
    'accepted': accepted,
  };

  static bool _addressInUse(SocketException e) {
    final code = e.osError?.errorCode;
    // EADDRINUSE: Linux 98, macOS 48, Windows WSAEADDRINUSE 10048.
    return code == 98 || code == 48 || code == 10048;
  }
}
