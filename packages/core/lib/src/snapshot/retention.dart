import 'package:core/src/errors.dart';

/// Политика хранения снимков (задача 5.3.5): сколько хранить последних,
/// почасовых, дневных, недельных и месячных. Как `restic forget --keep-*`:
/// в каждом часе (дне, неделе, месяце) остаётся самый новый снимок, не
/// больше заданного числа таких промежутков, считая от нового к старому.
/// Снимок остаётся, если его держит хоть одно правило.
///
/// Промежутки — в местном времени; неделя — ISO 8601 (с понедельника).
final class RetentionPolicy {
  const new({
    this.last = 1,
    this.hourly = 24,
    this.daily = 7,
    this.weekly = 4,
    this.monthly = 12,
  });

  /// Чтение с проверкой; отсутствующие поля — по умолчанию. Ошибка —
  /// [ConfigException].
  factory fromJson(Map<String, Object?> json, {String key = 'retention'}) {
    int count(String name, int fallback, {int min = 0}) {
      final value = json[name];
      if (value == null) return fallback;
      if (value is int && value >= min && value <= 100000) return value;
      throw ConfigException(
        key: '$key.$name',
        reason: 'целое число от $min до 100000',
      );
    }

    for (final name in json.keys) {
      if (!_fields.contains(name)) {
        throw ConfigException(key: '$key.$name', reason: 'неизвестное поле');
      }
    }
    return RetentionPolicy(
      last: count('last', defaults.last, min: 1),
      hourly: count('hourly', defaults.hourly),
      daily: count('daily', defaults.daily),
      weekly: count('weekly', defaults.weekly),
      monthly: count('monthly', defaults.monthly),
    );
  }

  /// По умолчанию: последний, сутки почасовых, неделя дневных, месяц
  /// недельных, год месячных.
  static const defaults = RetentionPolicy();

  static const _fields = {'last', 'hourly', 'daily', 'weekly', 'monthly'};

  /// Сколько последних снимков хранить всегда; не меньше 1: самый новый
  /// снимок политика не удаляет.
  final int last;
  final int hourly;
  final int daily;
  final int weekly;
  final int monthly;

  Map<String, Object?> toJson() => {
    'last': last,
    'hourly': hourly,
    'daily': daily,
    'weekly': weekly,
    'monthly': monthly,
  };

  /// Какие из [items] оставить, какие удалить; [time] — время создания
  /// снимка. Порядок [items] любой.
  ///
  /// План устойчив: если удалить снимки из [RetentionPlan.forget] (все или
  /// часть — например, при сбое посреди очистки) и составить план заново,
  /// оставляемые снимки те же. Самый новый снимок в каждом промежутке не
  /// меняется от удаления остальных.
  RetentionPlan<T> plan<T>(Iterable<T> items, DateTime Function(T) time) {
    final sorted = items.toList()..sort((a, b) => time(b).compareTo(time(a)));
    final reasons = <int, Set<RetentionRule>>{};
    void apply(RetentionRule rule, int count, Object Function(DateTime) key) {
      if (count == 0) return;
      Object? previous;
      var kept = 0;
      for (var i = 0; i < sorted.length && kept < count; i++) {
        final k = key(time(sorted[i]).toLocal());
        if (k == previous) continue;
        previous = k;
        kept++;
        (reasons[i] ??= {}).add(rule);
      }
    }

    apply(RetentionRule.last, last, (t) => t.microsecondsSinceEpoch);
    apply(
      RetentionRule.hourly,
      hourly,
      (t) => (t.year, t.month, t.day, t.hour),
    );
    apply(RetentionRule.daily, daily, (t) => (t.year, t.month, t.day));
    apply(RetentionRule.weekly, weekly, isoWeek);
    apply(RetentionRule.monthly, monthly, (t) => (t.year, t.month));
    return RetentionPlan._(
      keep: [
        for (var i = 0; i < sorted.length; i++)
          if (reasons[i] case final r?) (sorted[i], r),
      ],
      forget: [
        for (var i = 0; i < sorted.length; i++)
          if (!reasons.containsKey(i)) sorted[i],
      ],
    );
  }

  @override
  String toString() =>
      'последних $last, почасовых $hourly, дневных $daily, '
      'недельных $weekly, месячных $monthly';
}

/// Правило, по которому снимок остался.
enum RetentionRule { last, hourly, daily, weekly, monthly }

/// План очистки: [keep] — от нового к старому, с правилами, которые
/// держат снимок; [forget] — что удалить, тоже от нового к старому.
final class RetentionPlan<T> {
  const new _({required this.keep, required this.forget});

  final List<(T, Set<RetentionRule>)> keep;
  final List<T> forget;
}

/// Год и номер недели по ISO 8601: неделя принадлежит году, в который
/// попадает её четверг.
(int, int) isoWeek(DateTime t) {
  // Даты в UTC: переход на летнее время не сдвигает счёт дней.
  final day = DateTime.utc(t.year, t.month, t.day);
  final thursday = day.add(Duration(days: DateTime.thursday - day.weekday));
  final firstDay = DateTime.utc(thursday.year);
  final week = thursday.difference(firstDay).inDays ~/ 7 + 1;
  return (thursday.year, week);
}
