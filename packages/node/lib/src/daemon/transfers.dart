import 'dart:async';

/// Учёт текущих передач фрагментов для корректной остановки: после
/// [close] новые передачи не начинаются, а [close] ждёт завершения
/// начатых. На паузе ([paused]) новые передачи тоже не начинаются, но
/// начатые идут до конца.
///
/// Обработчики операций с фрагментами (задача 3.4) берут [Transfer] на
/// каждую передачу и закрывают его в `finally`.
final class TransferGate {
  int _active = 0;
  bool _closed = false;
  Completer<void>? _idle;

  /// Пауза по команде владельца (`cli node pause`).
  bool paused = false;

  int get active => _active;
  bool get closed => _closed;

  /// Новая передача или `null`, если узел на паузе или останавливается.
  Transfer? tryBegin() {
    if (_closed || paused) return null;
    _active++;
    return Transfer._(this);
  }

  void _end() {
    _active--;
    if (_active == 0) _wakeIdle();
  }

  void _wakeIdle() {
    if (_idle case final idle? when !idle.isCompleted) idle.complete();
  }

  /// Перестаёт ждать начатые передачи: [close] завершается сразу.
  void forceClose() {
    _closed = true;
    _wakeIdle();
  }

  /// Перестаёт пускать новые передачи и ждёт начатые не дольше [grace]
  /// или до [forceClose]. `true` — все завершились.
  Future<bool> close(Duration grace) async {
    _closed = true;
    if (_active == 0) return true;
    final idle = _idle ??= Completer<void>();
    try {
      await idle.future.timeout(grace);
      return _active == 0;
    } on TimeoutException {
      return false;
    }
  }
}

/// Одна передача; [end] можно звать повторно.
final class Transfer {
  new _(this._gate);

  final TransferGate _gate;
  bool _ended = false;

  void end() {
    if (_ended) return;
    _ended = true;
    _gate._end();
  }
}

/// Счётчики узла с запуска для `cli node stats`. Заполняют обработчики
/// операций (задача 3.4).
final class NodeStats {
  int bytesReceived = 0;
  int bytesSent = 0;
  int fragmentsReceived = 0;
  int fragmentsSent = 0;
  int fragmentsDeleted = 0;

  /// Отклонённые запросы: талон, квота, пауза, пределы.
  int requestsRejected = 0;

  Map<String, Object?> toJson() => {
    'bytesReceived': bytesReceived,
    'bytesSent': bytesSent,
    'fragmentsReceived': fragmentsReceived,
    'fragmentsSent': fragmentsSent,
    'fragmentsDeleted': fragmentsDeleted,
    'requestsRejected': requestsRejected,
  };
}
