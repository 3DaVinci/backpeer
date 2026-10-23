import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';

/// Событие журнала с полями, как у координатора: передаётся в
/// `Logger.info` и т. п. вместо строки.
///
/// Правило для полей: ни ключей (кроме открытых идентификаторов узла),
/// ни содержимого фрагментов, ни текста исключений сторонних пакетов.
final class LogEvent {
  const new(this.event, [this.fields = const {}]);

  final String event;
  final Map<String, Object?> fields;

  @override
  String toString() => event;
}

/// Файл журнала с ротацией по размеру: когда [path] дорастает до
/// [maxBytes], он становится `path.1`, `path.1` — `path.2` и так далее;
/// файлов вместе с текущим не больше [files].
final class RotatingLogFile implements StringSink {
  new(this.path, {required this.maxBytes, required this.files}) {
    File(path).parent.createSync(recursive: true);
    _open();
  }

  final String path;
  final int maxBytes;
  final int files;

  late RandomAccessFile _raf;
  int _size = 0;

  void _open() {
    _raf = File(path).openSync(mode: FileMode.append);
    _size = _raf.lengthSync();
  }

  @override
  void write(Object? object) {
    final bytes = utf8.encode('$object');
    if (_size > 0 && _size + bytes.length > maxBytes) _rotate();
    _raf.writeFromSync(bytes);
    _size += bytes.length;
  }

  @override
  void writeln([Object? object = '']) => write('$object\n');

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      write(objects.join(separator));

  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));

  void _rotate() {
    _raf.closeSync();
    final last = File('$path.${files - 1}');
    if (files > 1 && last.existsSync()) last.deleteSync();
    for (var i = files - 2; i >= 1; i--) {
      final f = File('$path.$i');
      if (f.existsSync()) f.renameSync('$path.${i + 1}');
    }
    final current = File(path);
    if (files > 1) {
      current.renameSync('$path.1');
    } else {
      current.deleteSync();
    }
    _open();
  }

  void flush() => _raf.flushSync();

  void close() {
    _raf
      ..flushSync()
      ..closeSync();
  }
}

/// Пишет записи `logging` строками JSON (JSON Lines): `ts`, `level`,
/// `logger`, `event`, поля события.
final class JsonLogWriter {
  new(this._sink);

  final StringSink _sink;
  StreamSubscription<LogRecord>? _subscription;

  void attach(Level level) {
    hierarchicalLoggingEnabled = false;
    Logger.root.level = level;
    _subscription = Logger.root.onRecord.listen(write);
  }

  Future<void> detach() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  void write(LogRecord record) {
    final object = record.object;
    final line = <String, Object?>{
      'ts': record.time.toUtc().toIso8601String(),
      'level': record.level.name.toLowerCase(),
      'logger': record.loggerName,
      'event': object is LogEvent ? object.event : record.message,
      if (object is LogEvent) ...object.fields,
      // Только тип: текст исключения может содержать данные собеседника.
      if (record.error != null) 'error': record.error.runtimeType.toString(),
      if (record.stackTrace != null) 'stack': record.stackTrace.toString(),
    };
    _sink.writeln(jsonEncode(line));
  }
}
