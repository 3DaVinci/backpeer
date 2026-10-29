import 'package:cli/src/commands/account.dart';
import 'package:cli/src/context.dart';
import 'package:core/core.dart';
import 'package:protocol/protocol.dart' as pb;

/// Дата и время для человека, местные: `2026-10-29 12:30`.
String formatTime(DateTime t) => t.toLocal().toString().substring(0, 16);

/// Доля в процентах, округлённая вниз: 99,9 % — не «100 %».
int percent(int part, int whole) => part * 100 ~/ whole;

/// Сводка состояния бэкапа (задача 4.5.1): учётная запись, локальный
/// индекс и здоровье сегментов по данным координатора (`GetBackupHealth`,
/// protocol.md, раздел 4.16). Узлы не опрашиваются, ничего не скачивается.
final class StatusCommand extends CliCommand {
  new(super.ctx);

  @override
  String get name => 'status';

  @override
  String get description =>
      'Состояние бэкапа: сколько сегментов здоровы, ремонтируются, в риске.';

  @override
  Future<int> run() async {
    final config = ctx.config();
    final session = await ctx.session(config);
    try {
      final local = session.index.storedSegments().length;
      final account = bytesToHex(session.keys.accountId).substring(0, 12);
      final login = config.login == null ? '' : ' (${config.login})';
      final url = config.coordinator;
      ctx.report.info(
        'Учётная запись $account$login, '
        '${url == null ? 'без координатора' : 'координатор $url'}.',
      );
      ctx.report.info('В локальном индексе сегментов: $local.');
      final client = session.client;
      pb.GetBackupHealthResponse? health;
      if (client == null) {
        ctx.report.info(
          'Здоровье бэкапа ведёт координатор; без него — cli verify.',
        );
      } else {
        try {
          health = await client.getBackupHealth(pb.GetBackupHealthRequest());
        } on CoordinatorException catch (e) {
          coordinatorFailure(e);
        }
        _printHealth(health);
      }
      final s = health?.summary;
      final troubled = s != null && (s.atRisk > 0 || s.lost > 0);
      final code = troubled ? ExitCode.partial : ExitCode.ok;
      ctx.report.result({
        'accountId': bytesToHex(session.keys.accountId),
        'coordinator': config.coordinator,
        'localSegments': local,
        'health': health == null ? null : _healthJson(health),
      }, exitCode: code);
      return code;
    } finally {
      await session.close();
    }
  }

  void _printHealth(pb.GetBackupHealthResponse health) {
    final s = health.summary;
    final segments = s.segments.toInt();
    ctx.report.info(
      'На координаторе сегментов: $segments, фрагменты занимают '
      '${formatSize(s.fragmentBytes.toInt())}.',
    );
    if (segments == 0) return;
    ctx.report.info(
      '  полностью здоровы: ${s.healthy}, с неполным запасом: ${s.reduced}, '
      'в риске (ниже порога ремонта): ${s.atRisk}, потеряны: ${s.lost}',
    );
    ctx.report.info(
      '  ремонтируются: ${s.repairing}; читаются сейчас (узлы в сети): '
      '${s.readableNow} из $segments',
    );
    final live = s.liveFragments.toInt();
    final audited = s.auditedFragments.toInt();
    final since = DateTime.fromMillisecondsSinceEpoch(
      health.auditedSinceUnixMs.toInt(),
    );
    final lastMs = s.lastAuditUnixMs.toInt();
    final last = lastMs == 0
        ? 'аудитов ещё не было'
        : 'последний аудит '
              '${formatTime(DateTime.fromMillisecondsSinceEpoch(lastMs))}';
    ctx.report.info(
      '  проверены аудитом с ${formatTime(since)}: $audited из $live '
      'фрагментов${live == 0 ? '' : ' (${percent(audited, live)} %)'}; $last',
    );
    if (s.lost > 0) {
      ctx.report.warn(
        'Потеряно сегментов: ${s.lost} — их данные не восстановить. '
        'Сделайте новый бэкап; какие снимки затронуты — cli verify --audits.',
        {'lost': s.lost.toInt()},
      );
    } else if (s.atRisk > 0) {
      ctx.report.warn(
        'В риске сегментов: ${s.atRisk}: координатор их ремонтирует.',
        {'atRisk': s.atRisk.toInt()},
      );
    }
  }

  static Map<String, Object?> _healthJson(pb.GetBackupHealthResponse h) {
    final s = h.summary;
    String? time(int ms) => ms == 0
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            ms,
            isUtc: true,
          ).toIso8601String();
    return {
      'segments': s.segments.toInt(),
      'healthy': s.healthy.toInt(),
      'reduced': s.reduced.toInt(),
      'atRisk': s.atRisk.toInt(),
      'lost': s.lost.toInt(),
      'repairing': s.repairing.toInt(),
      'readableNow': s.readableNow.toInt(),
      'liveFragments': s.liveFragments.toInt(),
      'auditedFragments': s.auditedFragments.toInt(),
      'auditedSince': time(h.auditedSinceUnixMs.toInt()),
      'lastAudit': time(s.lastAuditUnixMs.toInt()),
      'fragmentBytes': s.fragmentBytes.toInt(),
    };
  }
}
