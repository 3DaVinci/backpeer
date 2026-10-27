import 'dart:io';

import 'package:agent/src/desktop/gdbus.dart';

/// Системные уведомления (задача 5.3.4): агент работает без окна, поэтому
/// о проблемах с бэкапом сообщает сам.
abstract interface class Notifier {
  /// Для текущей ОС: Linux — `org.freedesktop.Notifications`, иначе пока
  /// нет (macOS и Windows — 5.6). `FS_AGENT_NOTIFY=none` — без уведомлений.
  factory forPlatform([Map<String, String>? environment]) {
    final env = environment ?? Platform.environment;
    if (env['FS_AGENT_NOTIFY'] == 'none' || !Platform.isLinux) {
      return const NoNotifier();
    }
    return DesktopNotifier();
  }

  /// Для журнала: `freedesktop`, `none`.
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
