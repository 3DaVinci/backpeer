/// Адрес приёмника отчётов о сбоях, вшитый в сборку
/// (`--dart-define=CRASH_REPORT_URL=...`; docs/spec/crash-reports.md,
/// docs/ops/admin.md). Пусто — отчёты только сохраняются локально.
const String crashReportUrl = String.fromEnvironment('CRASH_REPORT_URL');

/// Разбирает [value] в адрес приёмника. Пусто — `null`.
///
/// Принимает полный адрес `https://…/api/v1/crash-reports`; если задан
/// только хост или хост с `/`, дописывает путь приёмника. `http` разрешён
/// только для локального стенда (`localhost`, `127.0.0.1`, `[::1]`):
/// отчёт содержит стек, и по открытому каналу его отправлять нельзя.
Uri? resolveCrashReportUri([String value = crashReportUrl]) {
  final text = value.trim();
  if (text.isEmpty) return null;
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty) return null;
  if (uri.scheme != 'https' && uri.scheme != 'http') return null;
  if (uri.hasQuery || uri.hasFragment) return null;
  if (uri.scheme == 'http' && !_isLoopback(uri.host)) return null;
  if (uri.path.isEmpty || uri.path == '/') {
    return uri.replace(path: '/api/v1/crash-reports');
  }
  if (uri.path.endsWith('/')) {
    return uri.replace(path: '${uri.path}api/v1/crash-reports');
  }
  return uri;
}

bool _isLoopback(String host) =>
    host == 'localhost' ||
    host == '127.0.0.1' ||
    host == '::1' ||
    host == '[::1]';
