import 'dart:typed_data';

/// Учёт доступности узла (задача 2.6.2; protocol.md, раздел 4.9). Время
/// делится на интервалы по 15 минут; интервал засчитан, если в нём был
/// heartbeat или регистрация. Доступность — доля засчитанных интервалов
/// за последние 30 дней, а для узла моложе 30 дней — с момента
/// регистрации. Порог для размещения — 0,6 (`mvp-scope.md`), в этапе 4
/// доступность войдёт в репутацию.
///
/// Хранение: на каждые сутки UTC — 12 байт (96 битов), бит интервала `i`
/// суток — бит `i % 8` (младший — 0) байта `i ~/ 8`, как у `set_bit` для
/// `bytea` в PostgreSQL.
abstract final class Uptime {
  static const slot = Duration(minutes: 15);
  static const slotsPerDay = 96;
  static const int bytesPerDay = slotsPerDay ~/ 8;
  static const windowDays = 30;
  static const int windowSlots = windowDays * slotsPerDay;

  static final int _slotMs = slot.inMilliseconds;

  /// Номер интервала от начала эпохи Unix.
  static int slotAt(DateTime time) => time.millisecondsSinceEpoch ~/ _slotMs;

  static int dayOf(int slot) => slot ~/ slotsPerDay;

  static int bitOf(int slot) => slot % slotsPerDay;

  /// Пустые сутки.
  static Uint8List emptyDay() => Uint8List(bytesPerDay);

  /// Взводит бит интервала [slot] в сутках [day] (для тестов и расчёта
  /// без базы; в базе — `set_bit`).
  static void mark(Uint8List day, int slot) {
    final bit = bitOf(slot);
    day[bit >> 3] |= 1 << (bit & 7);
  }

  static bool _isSet(Uint8List day, int bit) =>
      day[bit >> 3] & (1 << (bit & 7)) != 0;

  /// Доступность на момент [now]: доля засчитанных интервалов в окне
  /// `[max(начало окна, регистрация), текущий интервал]`. [days] — битовые
  /// карты по номеру суток, лишние сутки не мешают.
  static double availability(
    Map<int, Uint8List> days, {
    required DateTime registeredAt,
    required DateTime now,
  }) {
    final last = slotAt(now);
    var first = last - windowSlots + 1;
    final registered = slotAt(registeredAt);
    if (registered > first) first = registered;
    if (first > last) return 0;
    var online = 0;
    for (var s = first; s <= last; s++) {
      final day = days[dayOf(s)];
      if (day != null && _isSet(day, bitOf(s))) online++;
    }
    return online / (last - first + 1);
  }
}
