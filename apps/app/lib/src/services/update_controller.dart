import 'dart:async';
import 'dart:io';

import 'package:app/src/services/preferences.dart';
import 'package:app/src/services/update_control.dart';
import 'package:app/src/services/updater.dart';
import 'package:core/core.dart';
import 'package:daemon_kit/daemon_kit.dart' show ServiceException;
import 'package:flutter/foundation.dart';

/// Что сейчас с обновлением.
enum UpdateState {
  /// Проверки ещё не было или обновления нет.
  idle,

  /// Идёт проверка манифеста.
  checking,

  /// Обновление есть; ждём установки (в том числе окончания бэкапа).
  available,

  /// Загрузка и установка.
  applying,

  /// Установлено (приложение может перезапускаться).
  done,

  /// Проверка или установка не удалась.
  failed,
}

/// Проверка и автоматическая установка обновлений (задача 5.8.2).
///
/// - при `preferences.autoUpdate` проверяет обновление при старте (через
///   [checkDelay]) и раз в [interval], а найдя — само скачивает и ставит;
/// - установка не начинается, пока [canApply] не разрешит (идёт бэкап):
///   тогда повтор через [retryWhenBusy], бэкап не прерывается;
/// - для Windows/macOS/AppImage установщик поднимает новую версию сам, и
///   приложение завершается через обратный вызов выхода; для `.deb`/`.rpm`
///   показывается
///   адрес пакета.
final class UpdateController extends ChangeNotifier {
  new({
    required this.control,
    required this.preferences,
    required this.canApply,
    this.checkDelay = const Duration(seconds: 30),
    this.interval = const Duration(hours: 6),
    this.retryWhenBusy = const Duration(minutes: 10),
    this.exitDelay = const Duration(seconds: 2),
    void Function()? onExit,
  }) : _onExit = onExit ?? _exitApp;

  final UpdateControl control;
  final Preferences preferences;

  /// Можно ли сейчас останавливать фоновые процессы (нет идущего бэкапа).
  final bool Function() canApply;
  final Duration checkDelay;
  final Duration interval;
  final Duration retryWhenBusy;
  final Duration exitDelay;
  final void Function() _onExit;

  UpdateState state = UpdateState.idle;
  UpdateManifest? manifest;
  UpdateOutcome? outcome;
  String? error;

  /// Была ли хоть одна проверка (для текста «ещё не проверяли»).
  bool checked = false;

  Timer? _timer;
  Timer? _startTimer;
  Timer? _retry;
  Timer? _exitTimer;
  bool _started = false;
  bool _applying = false;
  bool _disposed = false;

  bool get busy =>
      state == UpdateState.checking || state == UpdateState.applying;

  /// Обновление найдено, но сейчас идёт бэкап.
  bool get waitingForBackup => manifest != null && !canApply();

  /// Запускает периодическую проверку. Вызывается после первого кадра.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    unawaited(_readPreviousFailure());
    _startTimer = Timer(checkDelay, () => unawaited(_autoCheck()));
    _timer = Timer.periodic(interval, (_) => unawaited(_autoCheck()));
  }

  /// Итог прошлой попытки: приложение выходит ради установки, поэтому о
  /// неудаче узнаёт только следующий запуск. Без этого «обновление не
  /// встало» выглядело как «обновлений нет» (Windows, 12.11.2026).
  Future<void> _readPreviousFailure() async {
    String? message;
    try {
      message = await control.takeLastFailure();
    } on Object {
      // Итог — вспомогательный: проверку обновлений он не отменяет.
      message = null;
    }
    if (message == null || _disposed) return;
    state = UpdateState.failed;
    error = message;
    notifyListeners();
  }

  /// Проверить сейчас (кнопка и ручной запуск).
  Future<void> checkNow() => _check(automatic: false);

  Future<void> _autoCheck() async {
    if (!preferences.autoUpdate || _disposed) return;
    if (busy) return;
    if (manifest != null) {
      await _maybeApply();
      return;
    }
    await _check(automatic: true);
  }

  Future<void> _check({required bool automatic}) async {
    if (busy || _disposed) return;
    state = UpdateState.checking;
    error = null;
    notifyListeners();
    try {
      final found = await control.check();
      if (_disposed) return;
      checked = true;
      manifest = found;
      state = found == null ? UpdateState.idle : UpdateState.available;
    } on Object catch (e) {
      if (_disposed) return;
      checked = true;
      state = UpdateState.failed;
      error = _describe(e);
    }
    if (_disposed) return;
    notifyListeners();
    if (automatic && manifest != null && preferences.autoUpdate) {
      await _maybeApply();
    }
  }

  Future<void> _maybeApply() async {
    if (!preferences.autoUpdate) return;
    if (manifest == null || busy || _applying || _disposed) return;
    if (!canApply()) {
      // Идёт бэкап: не останавливаем процессы, попробуем позже.
      _retry?.cancel();
      _retry = Timer(retryWhenBusy, () => unawaited(_maybeApply()));
      notifyListeners();
      return;
    }
    await applyNow();
  }

  /// Скачать и установить найденное обновление. Ручной вызов не ждёт
  /// окончания бэкапа: пользователь сам попросил.
  Future<void> applyNow() async {
    final found = manifest;
    if (found == null || busy || _disposed) return;
    _applying = true;
    state = UpdateState.applying;
    error = null;
    notifyListeners();
    UpdateOutcome? result;
    try {
      result = await control.apply(found);
      if (_disposed) return;
      outcome = result;
      manifest = null;
      state = UpdateState.done;
    } on Object catch (e) {
      if (_disposed) return;
      state = UpdateState.failed;
      error = _describe(e);
    } finally {
      _applying = false;
      if (!_disposed) notifyListeners();
    }
    if (result != null && result.restartRequired && !_disposed) {
      _retry?.cancel();
      _exitTimer = Timer(exitDelay, _onExit);
    }
  }

  static String _describe(Object e) => switch (e) {
    CoordinatorException(:final message) => message,
    PreconditionException(:final message) => message,
    IntegrityException() => 'подпись или хэш пакета не совпали',
    ServiceException(:final message) => message,
    _ => '$e',
  };

  static void _exitApp() => exit(0);

  @override
  void dispose() {
    _disposed = true;
    _startTimer?.cancel();
    _timer?.cancel();
    _retry?.cancel();
    _exitTimer?.cancel();
    super.dispose();
  }
}
