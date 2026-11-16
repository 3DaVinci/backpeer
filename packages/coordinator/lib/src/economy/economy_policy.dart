/// Тарифы бартерной экономики (этап 7, docs/spec/economy.md).
///
/// Кредит — единица учёта: 1 CR = 0,5 ₽. Суммы в базе и API — в
/// микрокредитах (1 CR = 1 000 000 мк), чтобы ежедневные начисления не
/// теряли доли на мелких узлах.
final class EconomyPolicy {
  const new({
    this.dataCreditsPerTbMonth = 1200,
    this.storeCreditsPerTbMonth = 400,
    this.barterRatio = 2.5,
    this.starterCredits = 600,
    this.historyLimit = 20,
    this.graceDays = 7,
    this.repairWindowDays = 30,
  });

  /// Сколько кредитов стоит хранение 1 ТБ данных в месяц.
  final int dataCreditsPerTbMonth;

  /// Сколько кредитов получает хранитель за 1 ТБ занятых фрагментов в
  /// месяц (до веса доступности и аудитов).
  final int storeCreditsPerTbMonth;

  /// Отношение «ёмкость : данные» для бесплатной бартерной квоты:
  /// 2,5 ТБ объявленной ёмкости дают 1 ТБ хранения.
  final double barterRatio;

  /// Стартовый грант новому пользователю, CR. 600 CR = 0,5 ТБ·мес —
  /// типичный первый бэкап на месяц.
  final int starterCredits;

  /// Сколько последних проводок отдавать в `GetQuota`.
  final int historyLimit;

  /// Льготный период при отрицательном балансе, дней (задача 7.3.2). Пока
  /// он идёт, новые данные в пределах бесплатной квоты разрешены; после —
  /// запрещены. Сохранённые данные не удаляются.
  final int graceDays;

  /// За сколько суток показывать трафик ремонта как нагрузку хранителя
  /// (задача 7.4.3).
  final int repairWindowDays;

  static const int microPerCredit = 1000000;
  static const int tbBytes = 1000 * 1000 * 1000 * 1000;
  static const int daysPerMonth = 30;

  /// Микрокредиты за [credits] кредитов.
  int toMicro(int credits) => credits * microPerCredit;

  /// Стоимость хранения [bytes] данных за месяц, мк.
  int dataCostMicro(int bytes) => _costMicro(bytes, dataCreditsPerTbMonth);

  /// Плата хранителю за [bytes] занятых фрагментов за месяц, мк.
  int storeCostMicro(int bytes) => _costMicro(bytes, storeCreditsPerTbMonth);

  int _costMicro(int bytes, int creditsPerTb) =>
      (BigInt.from(bytes) *
              BigInt.from(creditsPerTb) *
              BigInt.from(microPerCredit) ~/
              BigInt.from(tbBytes))
          .toInt();

  /// Бесплатная квота за [capacityBytes] объявленной ёмкости.
  int barterBytes(int capacityBytes) => (capacityBytes / barterRatio).round();

  /// Сколько байт данных можно хранить на [micro] микрокредитов в месяц.
  int bytesForMicro(int micro) =>
      (BigInt.from(micro) *
              BigInt.from(tbBytes) ~/
              BigInt.from(dataCreditsPerTbMonth * microPerCredit))
          .toInt();
}
