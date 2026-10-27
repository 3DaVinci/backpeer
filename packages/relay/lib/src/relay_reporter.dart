import 'dart:async';

import 'package:core/core.dart';
import 'package:logging/logging.dart';
import 'package:relay/src/log.dart';
import 'package:relay/src/relay_server.dart';

/// Отчёты relay координатору (задачи 3.8.2, 3.8.3): каждые [interval] —
/// `ReportRelayUsage` с приростом трафика по учётным записям, числом
/// узлов и сеансов, подписанный ключом relay [key]. Координатор по ним
/// ведёт объём через relay на учётную запись и метрики. Отчёт, который не
/// дошёл, возвращается в счётчики и уходит со следующим.
final class RelayReporter {
  new({
    required this.client,
    required this.key,
    required this.server,
    this.interval = const Duration(seconds: 60),
  }) : _interval = interval;

  final CoordinatorClient client;
  final Ed25519KeyPair key;
  final RelayServer server;
  final Duration interval;
  Duration _interval;
  Timer? _timer;
  Future<void>? _sending;
  bool _stopped = false;

  /// Отчётов, принятых координатором, и последняя ошибка — для журнала.
  int reported = 0;
  String? lastError;

  static final _log = Logger('report');

  void start() => _schedule();

  /// Останавливает отчёты и отправляет последний.
  Future<void> stop() async {
    _stopped = true;
    _timer?.cancel();
    await report();
  }

  /// Отправляет прирост сейчас; одновременные вызовы ждут один отчёт.
  Future<void> report() => _sending ??= _send().whenComplete(() {
    _sending = null;
  });

  void _schedule() {
    if (_stopped) return;
    _timer = Timer(_interval, () async {
      await report();
      _schedule();
    });
  }

  Future<void> _send() async {
    final request = server.takeReport();
    try {
      final response = await client.reportRelayUsage(request, relayKey: key);
      reported++;
      lastError = null;
      if (response.nextReportMs > 0) {
        _interval = Duration(milliseconds: response.nextReportMs);
      }
      _log.fine(
        LogEvent('reported', {
          'bytes': request.bytes.toInt(),
          'accounts': request.usage.length,
        }),
      );
    } on CoordinatorException catch (e) {
      server.usage.restore(request);
      lastError = '${e.code.name}: ${e.detail}';
      _log.warning(
        LogEvent('report_failed', {
          'code': e.code.name,
          'http_status': e.httpStatus,
        }),
      );
    }
  }
}
