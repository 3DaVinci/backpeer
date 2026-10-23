import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

/// Ошибка локального API: код и сообщение для человека.
final class ControlException implements Exception {
  const new(this.code, this.message);

  /// `unavailable` (демон не запущен), `bad_request`, `unknown_method`,
  /// `forbidden`, `internal`.
  final String code;
  final String message;

  @override
  String toString() => 'ControlException($code): $message';
}

/// Где слушает локальный API демона (`docs/ops/node.md`, раздел
/// «Локальный API»):
///
/// - Linux и macOS — Unix-сокет `<data>/run/control.sock` (или
///   `control.socket`) в каталоге с правами 0700, сам сокет 0600; на Linux
///   демон ещё сверяет пользователя собеседника (`SO_PEERCRED`);
/// - Windows — Unix-сокетов в Dart там нет, а named pipe требует своей
///   реализации на Win32 API: TCP на 127.0.0.1 со случайным портом и
///   токеном. Порт и токен — в `<data>/run/control.json`, доступном только
///   владельцу; первым запросом клиент предъявляет токен.
final class ControlEndpoint {
  new({required this.runDir, String? socketPath})
    : socketPath = socketPath ?? '${runDir.path}/control.sock';

  /// Для папки данных узла [dataDir].
  factory forDataDir(String dataDir, {String? socketPath}) => ControlEndpoint(
    runDir: Directory('$dataDir/run'),
    socketPath: socketPath,
  );

  /// Наибольшая длина пути Unix-сокета: `sun_path` — 108 байт на Linux и
  /// 104 на macOS, с завершающим нулём.
  static const maxSocketPath = 103;

  final Directory runDir;
  final String socketPath;

  /// Файл с портом и токеном (Windows).
  File get tokenFile => File('${runDir.path}/control.json');

  static bool get usesUnixSocket => !Platform.isWindows;

  /// Порт и токен из [tokenFile]; нет файла — демон не запущен.
  (int, String) readToken() {
    final Object? json;
    try {
      json = jsonDecode(tokenFile.readAsStringSync());
    } on FileSystemException {
      throw const ControlException('unavailable', 'демон узла не запущен');
    } on FormatException {
      throw const ControlException('unavailable', 'control.json повреждён');
    }
    if (json case {'port': final int port, 'token': final String token}) {
      return (port, token);
    }
    throw const ControlException('unavailable', 'control.json повреждён');
  }
}

/// Пользователь процесса (`getuid`), Linux и macOS.
int currentUid() => _getuid();

final int Function() _getuid = DynamicLibrary.process()
    .lookupFunction<Uint32 Function(), int Function()>('getuid');

/// Пользователь процесса на том конце Unix-сокета: `struct ucred { pid,
/// uid, gid }` из `getsockopt(SOL_SOCKET, SO_PEERCRED)`, только Linux;
/// `null` — узнать не удалось.
int? peerUid(Socket socket) {
  if (!Platform.isLinux) return null;
  try {
    final value = socket.getRawOption(
      RawSocketOption(RawSocketOption.levelSocket, 17, Uint8List(12)),
    );
    return ByteData.sublistView(value).getUint32(4, Endian.host);
  } on Object {
    return null;
  }
}
