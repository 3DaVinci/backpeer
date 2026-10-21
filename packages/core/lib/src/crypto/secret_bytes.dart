import 'dart:typed_data';

/// Секретные байты: ключи, seed, общий секрет X25519. Отдельный тип, чтобы
/// секрет нельзя было случайно передать туда, где ждут обычные данные, и
/// чтобы он не попадал в лог: [toString] не показывает содержимое.
///
/// Байты копируются при создании. [dispose] затирает их нулями; после
/// этого обращение к [bytes] — [StateError].
final class SecretBytes {
  /// Копия [bytes].
  new(List<int> bytes) : _bytes = Uint8List.fromList(bytes);

  /// Забирает [bytes] без копирования; вызывающий больше не трогает буфер.
  new adopt(Uint8List bytes) : _bytes = bytes;

  final Uint8List _bytes;
  bool _disposed = false;

  int get length => _bytes.length;

  /// Содержимое для передачи в криптографическую реализацию. Ссылку не
  /// хранить и не выводить.
  Uint8List get bytes {
    if (_disposed) throw StateError('SecretBytes уже уничтожен');
    return _bytes;
  }

  bool get isDisposed => _disposed;

  void dispose() {
    _bytes.fillRange(0, _bytes.length, 0);
    _disposed = true;
  }

  @override
  String toString() => 'SecretBytes($length байт)';
}
