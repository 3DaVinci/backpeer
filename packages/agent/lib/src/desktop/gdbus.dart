import 'dart:io';

/// Вызов метода D-Bus программой `gdbus` из GLib (есть везде, где есть
/// libsecret: GNOME, KDE, XFCE). Свой клиент D-Bus на Dart не нужен, а
/// пакет `dbus` — под MPL-2.0 (ADR-010). [args] — аргументы метода в
/// текстовой записи GVariant ([gvariantString] для строк).
///
/// Возвращает вывод `gdbus` (`(<false>,)`, `(uint32 7,)`); нет программы,
/// шины или службы — `null`.
Future<String?> gdbusCall({
  required bool system,
  required String destination,
  required String objectPath,
  required String method,
  List<String> args = const [],
  Duration timeout = const Duration(seconds: 5),
}) async {
  try {
    final result = await Process.run('gdbus', [
      'call',
      if (system) '--system' else '--session',
      '--dest',
      destination,
      '--object-path',
      objectPath,
      '--method',
      method,
      '--timeout',
      '${timeout.inSeconds}',
      ...args,
    ]).timeout(timeout + const Duration(seconds: 1));
    if (result.exitCode != 0) return null;
    return (result.stdout as String).trim();
  } on ProcessException {
    return null;
  } on Exception {
    return null;
  }
}

/// Строка в текстовой записи GVariant: `'…'` с экранированием.
String gvariantString(String s) =>
    "'${s.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'";
