import 'dart:convert';
import 'dart:typed_data';

/// Кадры локального API: одна строка JSON на сообщение (JSON Lines,
/// UTF-8, `\n` в конце).
///
/// Запрос — `{"id": 1, "method": "status", "params": {…}}`, ответ —
/// `{"id": 1, "result": {…}}` или `{"id": 1, "error": {"code": …,
/// "message": …}}`. После метода `subscribe` сервер шлёт и события без
/// `id`: `{"event": "progress", "data": {…}}`. Строка длиннее [maxLine]
/// обрывает соединение.
abstract final class ControlWire {
  static const int maxLine = 64 << 10;

  static Uint8List encode(Map<String, Object?> message) =>
      utf8.encode('${jsonEncode(message)}\n');
}

/// Собирает строки из потока байтов.
final class LineReader {
  final _buffer = BytesBuilder(copy: false);

  /// Добавляет [chunk]; возвращает готовые сообщения. Строка длиннее
  /// [ControlWire.maxLine] или не JSON-объект — [FormatException].
  List<Map<String, Object?>> add(List<int> chunk) {
    final out = <Map<String, Object?>>[];
    var start = 0;
    for (var i = 0; i < chunk.length; i++) {
      if (chunk[i] != 0x0A) continue;
      _buffer.add(chunk.sublist(start, i));
      start = i + 1;
      out.add(_parse(_buffer.takeBytes()));
    }
    if (start < chunk.length) _buffer.add(chunk.sublist(start));
    if (_buffer.length > ControlWire.maxLine) {
      throw const FormatException('строка длиннее предела');
    }
    return out;
  }

  static Map<String, Object?> _parse(Uint8List line) {
    if (line.length > ControlWire.maxLine) {
      throw const FormatException('строка длиннее предела');
    }
    final Object? json = jsonDecode(utf8.decode(line));
    if (json is! Map<String, Object?>) {
      throw const FormatException('ожидается объект JSON');
    }
    return json;
  }
}
