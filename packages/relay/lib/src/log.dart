import 'dart:async';
import 'dart:convert';

import 'package:logging/logging.dart';

/// Событие журнала с полями, как у координатора: передаётся в
/// `Logger.info` и т. п. вместо строки.
///
/// Правило для полей: ни пропусков, ни IP-адресов, ни текста исключений
/// сторонних пакетов; ключи узлов — открытые идентификаторы, их можно.
final class LogEvent {
  const new(this.event, [this.fields = const {}]);

  final String event;
  final Map<String, Object?> fields;

  @override
  String toString() => event;
}

/// Пишет записи `logging` строками JSON (JSON Lines): `ts`, `level`,
/// `logger`, `event`, поля события.
final class JsonLogWriter {
  new(this._sink);

  final StringSink _sink;
  StreamSubscription<LogRecord>? _subscription;

  /// Подключается к корневому логгеру с уровнем [level].
  void attach(Level level) {
    hierarchicalLoggingEnabled = false;
    Logger.root.level = level;
    _subscription = Logger.root.onRecord.listen(write);
  }

  Future<void> detach() async {
    await _subscription?.cancel();
  }

  void write(LogRecord record) {
    final object = record.object;
    final line = <String, Object?>{
      'ts': record.time.toUtc().toIso8601String(),
      'level': record.level.name.toLowerCase(),
      'logger': record.loggerName,
      'event': object is LogEvent ? object.event : record.message,
      if (object is LogEvent) ...object.fields,
      if (record.error != null) 'error': record.error.runtimeType.toString(),
      if (record.stackTrace != null) 'stack': record.stackTrace.toString(),
    };
    _sink.writeln(jsonEncode(line));
  }
}
