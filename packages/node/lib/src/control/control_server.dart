import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:core/core.dart';
import 'package:logging/logging.dart';
import 'package:node/src/control/control_endpoint.dart';
import 'package:node/src/control/control_wire.dart';
import 'package:node/src/daemon/log.dart';

/// Обработчик метода локального API: результат или [ControlException].
typedef ControlHandler = Future<Map<String, Object?>> Function(
  String method,
  Map<String, Object?> params,
);

/// Сервер локального API демона ([ControlEndpoint]). Доступ — только
/// пользователю ОС, от которого запущен демон.
final class ControlServer {
  new _(this.endpoint, this._socket, this._handler, this._token, this._uid);

  /// Наибольшее число одновременных соединений: CLI и приложение.
  static const maxConnections = 16;

  /// Слушает [endpoint]. [allowedUid] — пользователь, которому можно
  /// подключаться (по умолчанию текущий; другой — только для тестов).
  static Future<ControlServer> bind(
    ControlEndpoint endpoint,
    ControlHandler handler, {
    int? allowedUid,
  }) async {
    final runDir = endpoint.runDir..createSync(recursive: true);
    if (!ControlEndpoint.usesUnixSocket) {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final token = bytesToHex(List.generate(32, (_) => _random.nextInt(256)));
      try {
        writePrivateFileAtomic(
          endpoint.tokenFile,
          ControlWire.encode({'port': socket.port, 'token': token}),
        );
      } on Object {
        await socket.close();
        rethrow;
      }
      final server = ControlServer._(endpoint, socket, handler, token, null);
      socket.listen(server._accept);
      return server;
    }
    setUnixFileMode(runDir.path, 448); // 0700
    final path = endpoint.socketPath;
    if (utf8.encode(path).length > ControlEndpoint.maxSocketPath) {
      throw FileSystemException(
        'путь сокета длиннее ${ControlEndpoint.maxSocketPath} байт: '
        'задайте control.socket покороче',
        path,
      );
    }
    await _removeStale(path);
    final socket = await ServerSocket.bind(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    try {
      setUnixFileMode(path, 384); // 0600
    } on Object {
      await socket.close();
      rethrow;
    }
    final server = ControlServer._(
      endpoint,
      socket,
      handler,
      null,
      Platform.isLinux ? (allowedUid ?? currentUid()) : null,
    );
    socket.listen(server._accept);
    return server;
  }

  static final _log = Logger('control');
  static final _random = Random.secure();

  final ControlEndpoint endpoint;
  final ServerSocket _socket;
  final ControlHandler _handler;

  /// Токен (Windows) или `null`.
  final String? _token;

  /// Допустимый пользователь собеседника (Linux) или `null`.
  final int? _uid;
  final _connections = <Socket>{};

  Future<void> close() async {
    await _socket.close();
    for (final c in _connections.toList()) {
      c.destroy();
    }
    if (ControlEndpoint.usesUnixSocket) {
      final file = File(endpoint.socketPath);
      if (file.existsSync()) file.deleteSync();
    } else if (endpoint.tokenFile.existsSync()) {
      endpoint.tokenFile.deleteSync();
    }
  }

  Future<void> _accept(Socket socket) async {
    if (_connections.length >= maxConnections) {
      _log.warning(const LogEvent('connection_refused', {'reason': 'limit'}));
      socket.destroy();
      return;
    }
    if (_uid != null) {
      final uid = peerUid(socket);
      if (uid != _uid) {
        _log.warning(
          LogEvent('connection_refused', {'reason': 'uid', 'uid': uid}),
        );
        socket.destroy();
        return;
      }
    }
    _connections.add(socket);
    final reader = LineReader();
    var authorized = _token == null;
    try {
      await for (final chunk in socket) {
        for (final request in reader.add(chunk)) {
          final id = request['id'];
          final method = request['method'];
          final params = request['params'] ?? const <String, Object?>{};
          Map<String, Object?> reply;
          if (method is! String || params is! Map<String, Object?>) {
            reply = _error(id, 'bad_request', 'нужны method и params');
          } else if (!authorized) {
            if (method == 'auth' &&
                params['token'] is String &&
                constantTimeEquals(
                  (params['token']! as String).codeUnits,
                  _token!.codeUnits,
                )) {
              authorized = true;
              reply = {'id': id, 'result': const <String, Object?>{}};
            } else {
              socket.add(
                ControlWire.encode(_error(id, 'forbidden', 'нужен токен')),
              );
              return;
            }
          } else {
            try {
              reply = {'id': id, 'result': await _handler(method, params)};
            } on ControlException catch (e) {
              reply = _error(id, e.code, e.message);
            } on Object catch (e, st) {
              _log.severe(
                LogEvent('handler_failed', {'method': method}),
                e,
                st,
              );
              reply = _error(id, 'internal', 'внутренняя ошибка демона');
            }
          }
          socket.add(ControlWire.encode(reply));
        }
      }
    } on FormatException catch (e) {
      _log.warning(LogEvent('connection_dropped', {'reason': e.message}));
    } on SocketException {
      // Клиент закрыл соединение.
    } finally {
      _connections.remove(socket);
      await socket.flush().catchError((_) {});
      socket.destroy();
    }
  }

  static Map<String, Object?> _error(Object? id, String code, String message) =>
      {
        'id': id,
        'error': {'code': code, 'message': message},
      };

  /// Оставшийся от прошлого запуска сокет удаляется, если на нём никто не
  /// слушает; файл другого типа и работающий демон — ошибка.
  static Future<void> _removeStale(String path) async {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return;
    if (type != FileSystemEntityType.unixDomainSock) {
      throw FileSystemException('не сокет, не удаляю', path);
    }
    try {
      final probe = await Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      );
      probe.destroy();
      throw FileSystemException('демон узла уже запущен', path);
    } on SocketException {
      File(path).deleteSync();
    }
  }
}
