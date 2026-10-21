import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  test('по умолчанию — durability.md: 10 из 20, ремонт при 16', () {
    final p = DurabilityParameters();
    expect((p.k, p.n, p.repairThreshold), (10, 20, 16));
    expect(p.minStoredFragments, 17);
    expect(DurabilityParameters.fromConfig(const {}).toConfig(), p.toConfig());
  });

  test('чтение из конфигурации', () {
    final p = DurabilityParameters.fromConfig(const {
      'k': 4,
      'n': 6,
      'repairThreshold': 5,
    });
    expect((p.k, p.n, p.minStoredFragments), (4, 6, 6));
    expect(
      DurabilityParameters.fromConfig(p.toConfig()).toConfig(),
      p.toConfig(),
    );
  });

  test('границы', () {
    expect(
      DurabilityParameters(k: 1, n: 2, repairThreshold: 1).minStoredFragments,
      2,
    );
    expect(DurabilityParameters(k: 200, n: 255, repairThreshold: 254).n, 255);
    for (final (k, n, t, key) in const [
      (0, 20, 16, 'k'),
      (10, 256, 16, 'n'),
      (10, 10, 10, 'n'),
      (11, 10, 10, 'n'),
      (10, 20, 9, 'repairThreshold'),
      (10, 20, 20, 'repairThreshold'),
    ]) {
      expect(
        () => DurabilityParameters(k: k, n: n, repairThreshold: t),
        throwsA(isA<ConfigException>().having((e) => e.key, 'key', key)),
        reason: '$k, $n, $t',
      );
    }
  });

  test('значение не целое — ConfigException', () {
    expect(
      () => DurabilityParameters.fromConfig(const {'k': '10'}),
      throwsA(isA<ConfigException>().having((e) => e.key, 'key', 'k')),
    );
    expect(
      () => DurabilityParameters.fromConfig(const {'n': 20.5}),
      throwsA(isA<ConfigException>()),
    );
  });
}
