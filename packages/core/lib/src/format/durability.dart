import 'package:core/src/errors.dart';

/// Параметры надёжности сегмента (docs/spec/durability.md): k из n и порог
/// ремонта t.
final class DurabilityParameters {
  /// Проверяет границы: `1 ≤ k < n ≤ 255` (n хранится в одном байте
  /// заголовка фрагмента) и `k ≤ t < n` (ремонт раньше потери данных).
  /// Нарушение — [ConfigException].
  factory({
    int k = defaultK,
    int n = defaultN,
    int repairThreshold = defaultRepairThreshold,
  }) {
    if (k < 1) throw ConfigException(key: 'k', reason: 'k = $k, нужно ≥ 1');
    if (n > 255) {
      throw ConfigException(key: 'n', reason: 'n = $n, нужно ≤ 255');
    }
    if (k >= n) {
      throw ConfigException(key: 'n', reason: 'n = $n, нужно больше k = $k');
    }
    if (repairThreshold < k || repairThreshold >= n) {
      throw ConfigException(
        key: 'repairThreshold',
        reason: 't = $repairThreshold, нужно k ≤ t < n ($k ≤ t < $n)',
      );
    }
    return DurabilityParameters._(k, n, repairThreshold);
  }

  /// Из раздела конфигурации; отсутствующие ключи — значения по умолчанию.
  factory fromConfig(Map<String, Object?> config) {
    int read(String key, int fallback) => switch (config[key]) {
      null => fallback,
      final int value => value,
      final value => throw ConfigException(
        key: key,
        reason: 'нужно целое число, получено «$value»',
      ),
    };
    return DurabilityParameters(
      k: read('k', defaultK),
      n: read('n', defaultN),
      repairThreshold: read('repairThreshold', defaultRepairThreshold),
    );
  }

  const new _(this.k, this.n, this.repairThreshold);

  static const int defaultK = 10;
  static const int defaultN = 20;
  static const int defaultRepairThreshold = 16;

  /// Число фрагментов данных.
  final int k;

  /// Всего фрагментов.
  final int n;

  /// Ремонт запускается, когда живых фрагментов осталось t.
  final int repairThreshold;

  /// Сегмент считается сохранённым, если загружено не меньше t + 1
  /// фрагментов (`CommitSegment`); остальные досоздаёт ремонт.
  int get minStoredFragments => repairThreshold + 1;

  Map<String, Object?> toConfig() => {
    'k': k,
    'n': n,
    'repairThreshold': repairThreshold,
  };

  @override
  String toString() => '$k из $n, ремонт при $repairThreshold';
}
