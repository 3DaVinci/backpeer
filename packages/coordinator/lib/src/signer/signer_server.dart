import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:coordinator/src/log.dart';
import 'package:coordinator/src/signer/signer_wire.dart';
import 'package:coordinator/src/signer/ticket_signing_service.dart';
import 'package:core/core.dart';
import 'package:logging/logging.dart';

/// Подписант на Unix-сокете [path]. Доступ к сокету — правами файла
/// (0660, группа веб-сервера) и, если заданы допустимые uid, проверкой
/// пользователя собеседника (`SO_PEERCRED`, только Linux).
final class SignerServer {
  new _(this.path, this._socket, this._service, this._allowedUids);

  /// Наибольшее число одновременных соединений: веб-серверу хватает
  /// одного, остальное — запас на перезапуск.
  static const maxConnections = 8;

  static Future<SignerServer> bind(
    String path,
    TicketSigningService service, {
    Set<int> allowedUids = const {},
  }) async {
    if (allowedUids.isNotEmpty && !Platform.isLinux) {
      throw UnsupportedError('проверка пользователя — только на Linux');
    }
    await _removeStale(path);
    final socket = await ServerSocket.bind(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    try {
      setUnixFileMode(path, 432); // 0660
    } on Object {
      await socket.close();
      rethrow;
    }
    final server = SignerServer._(path, socket, service, allowedUids);
    socket.listen(server._accept);
    _log.info(
      LogEvent('listening', {
        'key': bytesToHex(service.publicKey),
        'max_lifetime_min': service.maxLifetime.inMinutes,
        'uid_check': allowedUids.isNotEmpty,
      }),
    );
    return server;
  }

  static final _log = Logger('signer');

  final String path;
  final ServerSocket _socket;
  final TicketSigningService _service;
  final Set<int> _allowedUids;
  final _connections = <Socket>{};

  Future<void> close() async {
    await _socket.close();
    for (final c in _connections.toList()) {
      c.destroy();
    }
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
    _log.info(const LogEvent('stopped'));
  }

  Future<void> _accept(Socket socket) async {
    if (_connections.length >= maxConnections) {
      _log.warning(const LogEvent('connection_refused', {'reason': 'limit'}));
      socket.destroy();
      return;
    }
    if (_allowedUids.isNotEmpty) {
      final uid = _peerUid(socket);
      if (uid == null || !_allowedUids.contains(uid)) {
        _log.warning(
          LogEvent('connection_refused', {'reason': 'uid', 'uid': uid}),
        );
        socket.destroy();
        return;
      }
    }
    _connections.add(socket);
    final reader = FrameReader();
    try {
      await for (final chunk in socket) {
        reader.add(chunk);
        while (true) {
          final frame = reader.next();
          if (frame == null) break;
          socket.add(SignerWire.frame(await _service.handle(frame)));
        }
      }
    } on FormatException catch (e) {
      _log.warning(LogEvent('connection_dropped', {'reason': e.message}));
    } on SocketException {
      // Веб-сервер закрыл соединение.
    } finally {
      _connections.remove(socket);
      socket.destroy();
    }
  }

  /// Пользователь процесса на том конце сокета: `struct ucred { pid, uid,
  /// gid }` из `getsockopt(SOL_SOCKET, SO_PEERCRED)`.
  static int? _peerUid(Socket socket) {
    try {
      final value = socket.getRawOption(
        RawSocketOption(RawSocketOption.levelSocket, 17, Uint8List(12)),
      );
      return ByteData.sublistView(value).getUint32(4, Endian.host);
    } on Object {
      return null;
    }
  }

  /// Оставшийся от прошлого запуска сокет удаляется, если на нём никто не
  /// слушает; файл другого типа — ошибка.
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
      throw FileSystemException('подписант уже запущен', path);
    } on SocketException {
      File(path).deleteSync();
    }
  }
}
