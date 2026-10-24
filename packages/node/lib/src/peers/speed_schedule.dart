import 'package:node/src/daemon/config.dart';

/// Правило расписания пределов скорости (`limits.schedule`): дни недели,
/// промежуток времени и пределы на это время. Запись —
/// `[дни] ЧЧ:ММ-ЧЧ:ММ [upload=Б/с] [download=Б/с]`, например
/// `mon-fri 09:00-18:00 upload=1000000`: дни — `mon`…`sun`, списком через
/// запятую и промежутками (`mon-fri,sun`), без дней — каждый день.
/// Промежуток через полночь (`23:00-07:00`) относится к дню, в который
/// начинается. Не указанный предел берётся из основных настроек.
final class SpeedRule {
  const new({
    required this.days,
    required this.fromMinute,
    required this.toMinute,
    required this.source,
    this.uploadBytesPerSecond,
    this.downloadBytesPerSecond,
  });

  /// Разбирает запись правила; ошибка — [NodeConfigException].
  factory parse(String text) {
    final parts = text.trim().split(RegExp(r'\s+'));
    var i = 0;
    var days = const {1, 2, 3, 4, 5, 6, 7};
    if (parts.isNotEmpty && !parts[0].contains(':')) {
      days = _days(parts[0], text);
      i++;
    }
    if (i >= parts.length) throw _error(text, 'нет промежутка ЧЧ:ММ-ЧЧ:ММ');
    final range = RegExp(r'^(\d\d):(\d\d)-(\d\d):(\d\d)$')
        .firstMatch(parts[i++]);
    if (range == null) throw _error(text, 'промежуток — ЧЧ:ММ-ЧЧ:ММ');
    int minute(int g) {
      final h = int.parse(range.group(g)!);
      final m = int.parse(range.group(g + 1)!);
      if (h > 24 || m > 59 || (h == 24 && m != 0)) {
        throw _error(text, 'время ${range.group(g)}:${range.group(g + 1)}');
      }
      return h * 60 + m;
    }

    final from = minute(1);
    final to = minute(3);
    if (from == to || from == 24 * 60) throw _error(text, 'пустой промежуток');
    int? upload;
    int? download;
    for (; i < parts.length; i++) {
      final kv = RegExp(r'^(upload|download)=(\d+)$').firstMatch(parts[i]);
      final value = int.tryParse(kv?.group(2) ?? '');
      if (kv == null || value == null || value > 1 << 40) {
        throw _error(text, 'ожидается upload=Б/с или download=Б/с');
      }
      if (kv.group(1) == 'upload') {
        upload = value;
      } else {
        download = value;
      }
    }
    if (upload == null && download == null) {
      throw _error(text, 'нет ни upload, ни download');
    }
    return SpeedRule(
      days: days,
      fromMinute: from,
      toMinute: to,
      uploadBytesPerSecond: upload,
      downloadBytesPerSecond: download,
      source: text.trim(),
    );
  }

  /// Дни недели по [DateTime.weekday]: 1 — понедельник.
  final Set<int> days;
  final int fromMinute;

  /// Конец промежутка, не включается; меньше [fromMinute] — через полночь.
  final int toMinute;
  final int? uploadBytesPerSecond;
  final int? downloadBytesPerSecond;

  /// Запись правила, как в настройках.
  final String source;

  /// Действует ли правило в момент [local] (местное время).
  bool matches(DateTime local) {
    final minute = local.hour * 60 + local.minute;
    final day = local.weekday;
    if (fromMinute < toMinute) {
      return days.contains(day) && minute >= fromMinute && minute < toMinute;
    }
    final previous = day == 1 ? 7 : day - 1;
    return (days.contains(day) && minute >= fromMinute) ||
        (days.contains(previous) && minute < toMinute);
  }

  static const _dayNames = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

  static Set<int> _days(String spec, String text) {
    final out = <int>{};
    for (final item in spec.split(',')) {
      final range = item.split('-');
      if (range.length > 2) throw _error(text, 'дни: $item');
      final from = _dayNames.indexOf(range.first) + 1;
      final to = _dayNames.indexOf(range.last) + 1;
      if (from == 0 || to == 0) throw _error(text, 'дни: $item');
      // mon-fri, а также через воскресенье: fri-mon.
      for (var d = from; ; d = d % 7 + 1) {
        out.add(d);
        if (d == to) break;
      }
    }
    return out;
  }

  static NodeConfigException _error(String text, String detail) =>
      NodeConfigException('limits.schedule: «${text.trim()}»: $detail');
}

/// Расписание пределов скорости: первое подходящее правило задаёт
/// пределы, вне правил действуют основные (`limits.*_bytes_per_second`).
final class SpeedSchedule {
  const new([this.rules = const []]);

  /// Из записей правил ([SpeedRule.parse]).
  factory parse(Iterable<String> rules) =>
      SpeedSchedule([for (final r in rules) SpeedRule.parse(r)]);

  final List<SpeedRule> rules;

  /// Пределы в момент [local] при основных [base].
  SpeedLimits at(DateTime local, SpeedLimits base) {
    for (final r in rules) {
      if (r.matches(local)) {
        return SpeedLimits(
          uploadBytesPerSecond:
              r.uploadBytesPerSecond ?? base.uploadBytesPerSecond,
          downloadBytesPerSecond:
              r.downloadBytesPerSecond ?? base.downloadBytesPerSecond,
        );
      }
    }
    return base;
  }

  List<String> toJson() => [for (final r in rules) r.source];
}
