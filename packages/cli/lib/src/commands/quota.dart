import 'package:cli/src/account_ops.dart';
import 'package:cli/src/commands/status.dart' show formatTime;
import 'package:cli/src/context.dart';
import 'package:core/core.dart';
import 'package:protocol/protocol.dart' as pb;

/// Баланс и квота учётной записи (этап 7, метод `GetQuota`).
///
/// Показывает, сколько данных уже сохранено, сколько даёт бесплатная
/// бартерная квота за отданное место, сколько добавят кредиты и на сколько
/// дней хватит баланса. Ничего не скачивает.
final class QuotaCommand extends CliCommand {
  new(super.ctx);

  @override
  String get name => 'quota';

  @override
  String get description => 'Квота и кредиты: сколько можно хранить и почему.';

  @override
  Future<int> run() async {
    final config = ctx.config();
    final session = await ctx.session(config);
    try {
      final client = session.client;
      if (client == null) {
        ctx.report.warn('Координатор не настроен: квоту считать не по чему.');
        return ExitCode.ok;
      }
      final pb.GetQuotaResponse quota;
      try {
        quota = await client.getQuota(
          pb.GetQuotaRequest(),
          accountKey: session.keys.accountSign,
        );
      } on CoordinatorException catch (e) {
        coordinatorFailure(e);
      }
      _print(quota);
      final data = quota.dataBytes.toInt();
      final max = quota.maxBytes.toInt();
      final code = data > max ? ExitCode.partial : ExitCode.ok;
      ctx.report.result({
        'dataBytes': data,
        'capacityBytes': quota.capacityBytes.toInt(),
        'barterBytes': quota.barterBytes.toInt(),
        'balanceMc': quota.balanceMc.toInt(),
        'maxBytes': max,
        'billableBytes': quota.billableBytes.toInt(),
        'monthlyCostMc': quota.monthlyCostMc.toInt(),
        'dailyCostMc': quota.dailyCostMc.toInt(),
        'earnedMc': quota.earnedMc.toInt(),
        'spentMc': quota.spentMc.toInt(),
        'negativeSince': quota.negativeSinceUnixMs.toInt() == 0
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                quota.negativeSinceUnixMs.toInt(),
                isUtc: true,
              ).toIso8601String(),
        'graceDays': quota.graceDays,
        'blocked': quota.blocked,
        'repairBytes': quota.repairBytes.toInt(),
        'repairCostMc': quota.repairCostMc.toInt(),
        'repairWindowDays': quota.repairWindowDays,
        'entries': [
          for (final e in quota.entries)
            {
              'kind': e.kind,
              'amountMc': e.amountMc.toInt(),
              'at': DateTime.fromMillisecondsSinceEpoch(
                e.atUnixMs.toInt(),
                isUtc: true,
              ).toIso8601String(),
              'note': e.note,
            },
        ],
      }, exitCode: code);
      return code;
    } finally {
      await session.close();
    }
  }

  void _print(pb.GetQuotaResponse q) {
    final data = q.dataBytes.toInt();
    final barter = q.barterBytes.toInt();
    final max = q.maxBytes.toInt();
    final billable = q.billableBytes.toInt();
    final balance = q.balanceMc.toInt();
    ctx.report.info('Сохранено данных: ${formatSize(data)}.');
    ctx.report.info(
      'Бесплатная квота за отданное место: ${formatSize(barter)} '
      '(ёмкость ${formatSize(q.capacityBytes.toInt())}, 2,5:1).',
    );
    ctx.report.info('Доступно для хранения: ${formatSize(max)}.');
    if (billable > 0) {
      ctx.report.info(
        'Сверх квоты: ${formatSize(billable)}; '
        '${_credits(q.monthlyCostMc.toInt())} CR в месяц '
        '(${_credits(q.dailyCostMc.toInt())} CR в день).',
      );
    }
    final sign = balance < 0 ? '−' : '';
    ctx.report.info(
      'Баланс: $sign${_credits(balance.abs())} CR; '
      'начислено ${_credits(q.earnedMc.toInt())} CR, '
      'списано ${_credits(q.spentMc.toInt())} CR.',
    );
    final daily = q.dailyCostMc.toInt();
    if (daily > 0) {
      final days = balance <= 0 ? 0 : balance ~/ daily;
      ctx.report.info('Баланса хватит примерно на $days дн.');
    }
    final repair = q.repairBytes.toInt();
    if (repair > 0) {
      ctx.report.info(
        'Трафик ремонта за ${q.repairWindowDays} сут: ${formatSize(repair)} '
        '(${_credits(q.repairCostMc.toInt())} CR по тарифу хранителя; '
        'отдельно не списывается).',
      );
    }
    if (balance < 0) {
      if (q.blocked) {
        ctx.report.warn(
          'Баланс отрицательный дольше ${q.graceDays} дн.: новые бэкапы '
          'запрещены, сохранённые данные не удаляются. Включите хранитель, '
          'чтобы начислять кредиты, или освободите место.',
        );
      } else {
        final sinceMs = q.negativeSinceUnixMs.toInt();
        if (sinceMs == 0) {
          ctx.report.warn(
            'Баланс отрицательный. Отметка о начале долга появится после '
            'ближайшего суточного расчёта; сохранённые данные не удаляются.',
          );
        } else {
          final since = DateTime.fromMillisecondsSinceEpoch(
            sinceMs,
            isUtc: true,
          );
          final until = since.add(Duration(days: q.graceDays));
          ctx.report.warn(
            'Баланс отрицательный с ${formatTime(since)}. Льготный период до '
            '${formatTime(until)}: новые данные в пределах бесплатной квоты '
            'разрешены. Потом новые бэкапы запретим; сохранённые данные '
            'не удаляются.',
          );
        }
      }
    }
    if (data > max) {
      ctx.report.warn(
        'Данных больше доступного: новые бэкапы заблокированы, '
        'сохранённые данные не удаляются.',
      );
    }
    if (q.entries.isNotEmpty) {
      ctx.report.info('Последние проводки:');
      for (final e in q.entries) {
        final at = DateTime.fromMillisecondsSinceEpoch(e.atUnixMs.toInt());
        final amount = e.amountMc.toInt();
        final text = amount < 0
            ? '−${_credits(-amount)} CR'
            : '+${_credits(amount)} CR';
        ctx.report.info('  ${formatTime(at)} $text ${e.kind} ${e.note}');
      }
    }
  }

  static String _credits(int micro) {
    final value = micro / 1000000;
    return value == value.roundToDouble()
        ? value.round().toString()
        : value.toStringAsFixed(2).replaceAll('.', ',');
  }
}
