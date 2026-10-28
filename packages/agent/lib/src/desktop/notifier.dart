import 'dart:io';

import 'package:agent/src/desktop/gdbus.dart';

/// Системные уведомления (задача 5.3.4): агент работает без окна, поэтому
/// о проблемах с бэкапом сообщает сам.
abstract interface class Notifier {
  /// Для текущей ОС: Linux — `org.freedesktop.Notifications`, macOS —
  /// `osascript`, Windows — всплывающее сообщение области уведомлений
  /// (PowerShell). `FS_AGENT_NOTIFY=none` — без уведомлений.
  factory forPlatform([Map<String, String>? environment]) {
    final env = environment ?? Platform.environment;
    if (env['FS_AGENT_NOTIFY'] == 'none') return const NoNotifier();
    if (Platform.isLinux) return DesktopNotifier();
    if (Platform.isMacOS) return const OsascriptNotifier();
    if (Platform.isWindows) return const PowerShellNotifier();
    return const NoNotifier();
  }

  /// Для журнала: `freedesktop`, `osascript`, `powershell`, `none`.
  String get name;

  /// Показать уведомление; [critical] — не исчезает само. Ошибки не
  /// бросает: результат — показано ли.
  Future<bool> notify(String title, String body, {bool critical = false});
}

final class NoNotifier implements Notifier {
  const new();

  @override
  String get name => 'none';

  @override
  Future<bool> notify(
    String title,
    String body, {
    bool critical = false,
  }) async => false;
}

/// Linux: `org.freedesktop.Notifications.Notify` по шине сеанса (GNOME,
/// KDE и другие). Новое уведомление заменяет прежнее агента.
final class DesktopNotifier implements Notifier {
  new({this.appName = 'file_storage'});

  final String appName;
  int _lastId = 0;

  @override
  String get name => 'freedesktop';

  @override
  Future<bool> notify(
    String title,
    String body, {
    bool critical = false,
  }) async {
    final out = await gdbusCall(
      system: false,
      destination: 'org.freedesktop.Notifications',
      objectPath: '/org/freedesktop/Notifications',
      method: 'org.freedesktop.Notifications.Notify',
      args: [
        gvariantString(appName),
        'uint32 $_lastId',
        gvariantString(critical ? 'dialog-error' : 'dialog-warning'),
        gvariantString(title),
        gvariantString(body),
        '@as []',
        // Срочность: 1 — обычная, 2 — критичная.
        "{'urgency': <byte ${critical ? 2 : 1}>}",
        'int32 -1',
      ],
    );
    if (out == null) return false;
    final id = RegExp(r'uint32 (\d+)').firstMatch(out);
    if (id != null) _lastId = int.parse(id[1]!);
    return true;
  }
}

/// macOS: `display notification` из AppleScript. Уведомление приходит от
/// имени «Редактора скриптов», пока у агента нет своего бандла (5.7.2).
final class OsascriptNotifier implements Notifier {
  const new();

  @override
  String get name => 'osascript';

  /// Строка AppleScript в кавычках.
  static String quote(String s) =>
      '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

  @override
  Future<bool> notify(
    String title,
    String body, {
    bool critical = false,
  }) async {
    try {
      final result = await Process.run('osascript', [
        '-e',
        'display notification ${quote(body)} with title ${quote(title)}',
      ]);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }
}

/// Windows: всплывающее сообщение значка области уведомлений
/// (`System.Windows.Forms.NotifyIcon`) из PowerShell; текст — через
/// переменные окружения, без экранирования.
final class PowerShellNotifier implements Notifier {
  const new();

  @override
  String get name => 'powershell';

  static const _script =
      'Add-Type -AssemblyName System.Windows.Forms; '
      r'$n = New-Object System.Windows.Forms.NotifyIcon; '
      r'$n.Icon = [System.Drawing.SystemIcons]::Warning; '
      r'$n.Visible = $true; '
      r'$n.ShowBalloonTip(15000, $env:FS_NOTIFY_TITLE, $env:FS_NOTIFY_BODY, '
      r'$env:FS_NOTIFY_LEVEL); '
      r'Start-Sleep -Seconds 15; $n.Dispose()';

  @override
  Future<bool> notify(
    String title,
    String body, {
    bool critical = false,
  }) async {
    try {
      await Process.start(
        'powershell.exe',
        [
          '-NoProfile',
          '-NonInteractive',
          '-WindowStyle',
          'Hidden',
          '-Command',
          _script,
        ],
        environment: {
          'FS_NOTIFY_TITLE': title,
          'FS_NOTIFY_BODY': body,
          'FS_NOTIFY_LEVEL': critical ? 'Error' : 'Warning',
        },
        mode: ProcessStartMode.detached,
      );
      return true;
    } on ProcessException {
      return false;
    }
  }
}

/// Для тестов: уведомления копятся в [sent].
final class MemoryNotifier implements Notifier {
  final sent = <(String, String)>[];

  @override
  String get name => 'memory';

  @override
  Future<bool> notify(
    String title,
    String body, {
    bool critical = false,
  }) async {
    sent.add((title, body));
    return true;
  }
}
