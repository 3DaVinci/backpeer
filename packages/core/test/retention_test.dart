// Политика хранения снимков (задача 5.3.5): месяц почасовых бэкапов на
// ускоренных часах оставляет число снимков по политике, план устойчив к
// обрыву посреди очистки; очистка по политике и сборка мусора освобождают
// место. Оценка объёма бэкапа (5.3.1).

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  group('политика хранения', () {
    // Месяц почасовых бэкапов: 30 суток × 24 = 720 снимков.
    final start = DateTime(2026, 10, 1, 0, 30);
    final hourly = [
      for (var i = 0; i < 720; i++) start.add(Duration(hours: i)),
    ];

    test('месяц почасовых — число снимков по политике', () {
      final plan = RetentionPolicy.defaults.plan(hourly, (t) => t);
      // 24 почасовых — последние 24 часа; 7 дневных и 4 недельных; из
      // 12 месячных есть только октябрь.
      final kept = {for (final (t, _) in plan.keep) t};
      final last24 = hourly.reversed.take(24).toSet();
      expect(kept.containsAll(last24), isTrue);
      final days = <(int, int, int)>{
        for (final t in hourly) (t.year, t.month, t.day),
      };
      expect(days, hasLength(30));
      // Дневные: самый новый снимок каждого из последних 7 дней.
      final daily = [
        for (final (t, rules) in plan.keep)
          if (rules.contains(RetentionRule.daily)) t,
      ];
      expect(daily, hasLength(7));
      for (final t in daily) {
        expect(t.hour, anyOf(23, hourly.last.hour));
      }
      final weekly = [
        for (final (t, rules) in plan.keep)
          if (rules.contains(RetentionRule.weekly)) t,
      ];
      expect(weekly, hasLength(4));
      final monthly = [
        for (final (t, rules) in plan.keep)
          if (rules.contains(RetentionRule.monthly)) t,
      ];
      expect(monthly, [hourly.last]);
      // Всего — объединение правил: снимки, которые держат несколько
      // правил, считаются один раз.
      final expected = {...last24, ...daily, ...weekly, ...monthly};
      expect(kept, expected);
      expect(plan.keep.length + plan.forget.length, 720);
      expect(plan.keep.length, lessThan(24 + 7 + 4 + 1 + 1));
      expect(plan.keep.first.$1, hourly.last, reason: 'от нового к старому');
    });

    test('обрыв посреди очистки не трогает то, что держит политика', () {
      final rnd = Random(5);
      const policy = RetentionPolicy(last: 3, hourly: 10, daily: 5);
      final times = [
        for (var i = 0; i < 300; i++)
          start.add(Duration(minutes: rnd.nextInt(60 * 24 * 20))),
      ];
      final plan = policy.plan(times, (t) => t);
      final kept = [for (final (t, _) in plan.keep) t];
      // Удалена только часть, в случайном порядке: план тот же.
      for (var round = 0; round < 10; round++) {
        final removed = (plan.forget.toList()..shuffle(rnd)).take(
          rnd.nextInt(plan.forget.length),
        );
        final left = times.toSet().difference(removed.toSet());
        final again = policy.plan(left, (t) => t);
        expect([for (final (t, _) in again.keep) t], kept);
        expect(again.forget.toSet(), left.difference(kept.toSet()));
      }
    });

    test('самый новый остаётся всегда; недели по ISO 8601', () {
      const policy = RetentionPolicy(
        hourly: 0,
        daily: 0,
        weekly: 0,
        monthly: 0,
      );
      final plan = policy.plan(hourly, (t) => t);
      expect(plan.keep.single.$1, hourly.last);
      expect(isoWeek(DateTime(2026)), (2026, 1));
      expect(isoWeek(DateTime(2027)), (2026, 53));
      expect(isoWeek(DateTime(2024, 12, 30)), (2025, 1));
      expect(isoWeek(DateTime(2026, 10, 27)), (2026, 44));
    });

    test('чтение и проверка', () {
      final p = RetentionPolicy.fromJson({'hourly': 48, 'monthly': 3});
      expect(p.hourly, 48);
      expect(p.daily, RetentionPolicy.defaults.daily);
      expect(RetentionPolicy.fromJson(p.toJson()).toJson(), p.toJson());
      for (final bad in [
        {'last': 0},
        {'daily': -1},
        {'weekly': 'две'},
        {'yearly': 1},
      ]) {
        expect(
          () => RetentionPolicy.fromJson(bad),
          throwsA(isA<ConfigException>()),
          reason: '$bad',
        );
      }
    });
  });

  group('очистка и оценка', () {
    late CryptoProvider crypto;
    late AccountKeys keys;
    final deviceId = Uint8List(32)..[0] = 0xDE;
    final otherDevice = Uint8List(32)..[0] = 0xEF;
    setUpAll(() async {
      crypto = await SodiumCryptoProvider.load();
      keys = await AccountKeys.fromPhrase(
        RecoveryPhrase.fromEntropy(Uint8List(32)),
        crypto,
      );
    });

    late Directory dir;
    late LocalIndex index;
    late LocalFolderStore nodes;
    late LocalObjectStore objects;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('fs-retention-');
      index = LocalIndex.open('${dir.path}/index.db');
      nodes = LocalFolderStore(
        Directory('${dir.path}/nodes'),
        crypto,
        nodeCount: 6,
      );
      objects = LocalObjectStore(Directory('${dir.path}/objects'));
    });
    tearDown(() {
      index.close();
      dir.deleteSync(recursive: true);
    });

    final params = DurabilityParameters(k: 2, n: 4, repairThreshold: 3);
    SnapshotCatalog catalog() => SnapshotCatalog(
      crypto: crypto,
      manifestKey: keys.manifestKey,
      store: objects,
      index: index,
    );

    int nodeBytes() =>
        Directory('${dir.path}/nodes')
            .listSync(recursive: true)
            .whereType<File>()
            .fold(0, (sum, f) => sum + f.lengthSync());

    test('политика удаляет лишние снимки устройства, сборка мусора — '
        'их сегменты; чужие снимки не трогаются', () async {
      final data = Directory('${dir.path}/data')..createSync();
      final rnd = Random(1);
      Future<void> backup(Uint8List device) async {
        // Каждый раз новый файл: у каждого снимка свои сегменты.
        File(
          '${data.path}/f.bin',
        ).writeAsBytesSync(List.generate(200 << 10, (_) => rnd.nextInt(256)));
        await runBackup(
          crypto: crypto,
          keys: keys,
          index: index,
          fragments: nodes,
          objects: objects,
          paths: [data.path],
          deviceId: device,
          params: params,
        );
      }

      for (var i = 0; i < 4; i++) {
        await backup(deviceId);
      }
      await backup(otherDevice);
      final before = nodeBytes();
      const policy = RetentionPolicy(
        last: 2,
        hourly: 0,
        daily: 0,
        weekly: 0,
        monthly: 0,
      );
      final dry = await forgetByPolicy(
        catalog: catalog(),
        policy: policy,
        deviceId: deviceId,
        dryRun: true,
      );
      expect(dry.forgotten, hasLength(2));
      expect((await catalog().list()).snapshots, hasLength(5));

      final report = await forgetByPolicy(
        catalog: catalog(),
        policy: policy,
        deviceId: deviceId,
      );
      expect(report.kept, hasLength(2));
      expect(report.other, 1);
      final left = (await catalog().list()).snapshots;
      expect(left, hasLength(3));
      expect(left.where((s) => s.deviceId[0] == 0xEF), hasLength(1));

      final gc = await collectGarbage(
        crypto: crypto,
        keys: keys,
        index: index,
        fragments: nodes,
        objects: objects,
        releaser: LocalSegmentReleaser(index, nodes),
      );
      expect(gc.segmentsDeleted, greaterThan(0));
      expect(nodeBytes(), lessThan(before));
      // Повтор ничего не удаляет.
      final again = await forgetByPolicy(
        catalog: catalog(),
        policy: policy,
        deviceId: deviceId,
      );
      expect(again.forgotten, isEmpty);
    });

    test('оценка объёма учитывает исключения и готовые наборы', () {
      final data = Directory('${dir.path}/est')..createSync();
      File('${data.path}/doc.txt').writeAsStringSync('x' * 1000);
      File('${data.path}/draft.tmp').writeAsStringSync('y' * 500);
      Directory('${data.path}/.cache').createSync();
      File('${data.path}/.cache/blob').writeAsStringSync('z' * 4000);
      Directory('${data.path}/sub').createSync();
      File('${data.path}/sub/a.log').writeAsStringSync('w' * 10);

      final all = estimateBackup([data.path]);
      expect(all.files, 4);
      expect(all.bytes, 5510);
      final some = estimateBackup(
        [data.path, '${dir.path}/нет такой'],
        excludes: ExcludeRules([
          ...ExcludePreset.temporary.rules,
          ...ExcludePreset.caches.rules,
          '*.log',
        ]),
      );
      expect(some.files, 1);
      expect(some.bytes, 1000);
      expect(some.directories, 2);
      expect(some.excluded, 3);
      expect(some.skipped, hasLength(1));
      expect(some.toJson()['skippedFiles'], hasLength(1));
      expect(estimateBackup([data.path], maxEntries: 2).truncated, isTrue);
    });
  });
}
