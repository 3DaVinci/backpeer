// Фоновая проверка целостности фрагментов (задача 3.2.4).

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:node/node.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late CryptoProvider crypto;
  late Directory dir;
  late FragmentStorage storage;
  var now = DateTime.utc(2026, 10, 25, 12);
  setUpAll(() async => crypto = await SodiumCryptoProvider.load());
  setUp(() {
    now = DateTime.utc(2026, 10, 25, 12);
    dir = Directory.systemTemp.createTempSync('fs-node-check-');
    storage = FragmentStorage.open(
      dir.path,
      crypto: crypto,
      quotaBytes: 1 << 40,
      freeReserveBytes: 0,
      diskAvailable: (_) => null,
      clock: () => now,
    );
  });
  tearDown(() async {
    await storage.close();
    dir.deleteSync(recursive: true);
  });

  Future<Uint8List> put(int seed) async {
    final f = testFragment(crypto, seed: seed, blobLength: 200000);
    final id = fragmentIdOf(crypto, f);
    final incoming = await storage.beginPut(
      fragmentId: id,
      size: f.bytes.length,
      accountId: Uint8List(32),
    );
    await incoming.add(f.bytes);
    await incoming.commit();
    return id;
  }

  IntegrityChecker checker({void Function(FragmentCheck)? onDamaged}) =>
      IntegrityChecker(
        storage: storage,
        crypto: crypto,
        bytesPerSecond: 0,
        onDamaged: onDamaged,
        clock: () => now,
      );

  test('испорченный вручную и пропавший фрагменты обнаруживаются и '
      'попадают в отчёт', () async {
    final ok = await put(1);
    final corrupted = await put(2);
    final missing = await put(3);
    final damagedFound = <String>[];
    final c = checker(
      onDamaged: (r) => damagedFound.add(bytesToHex(r.fragmentId)),
    );

    // Только что принятые фрагменты проверены при приёме.
    expect(await c.checkNext(), isNull);

    // Порча одного байта тела на диске и удаление файла.
    final file = storage.files.fileOf(corrupted);
    final bytes = file.readAsBytesSync();
    bytes[bytes.length ~/ 2] ^= 0x40;
    file.writeAsBytesSync(bytes);
    storage.files.fileOf(missing).deleteSync();

    now = now.add(const Duration(days: 31));
    final results = <FragmentCheck>[];
    for (FragmentCheck? r; (r = await c.checkNext()) != null;) {
      results.add(r!);
    }
    expect(results, hasLength(3), reason: 'каждый фрагмент — один раз');
    expect(c.checked, 3);
    expect(c.damaged, 2);
    expect(damagedFound.toSet(), {bytesToHex(corrupted), bytesToHex(missing)});

    expect(storage.record(ok)!.state, FragmentState.stored);
    expect(storage.record(ok)!.checkedAt, now);
    final bad = storage.record(corrupted)!;
    expect(bad.state, FragmentState.damaged);
    expect(bad.damage, contains('корень дерева'));
    expect(storage.record(missing)!.damage, contains('пропал'));
    expect(storage.damagedCount, 2);
    expect(storage.fragmentCount, 3, reason: 'место занято до ремонта');

    // Повреждённые не выдаются.
    expect(storage.has(Uint8List(32), [ok, corrupted]), [true, false]);
    expect(
      () => storage.openRead(corrupted),
      throwsA(isA<FragmentStorageException>()),
    );

    // Отчёт: пока координатор не принял — в списке.
    final report = storage.unreportedDamaged();
    expect(report.map(bytesToHex).toSet(), damagedFound.toSet());
    storage.markReported(report);
    expect(storage.unreportedDamaged(), isEmpty);

    // Повреждённые больше не проверяются; удаление освобождает место.
    now = now.add(const Duration(days: 31));
    expect((await c.checkNext())!.fragmentId, ok);
    expect(await c.checkNext(), isNull);
    expect(storage.delete(corrupted), isTrue);
    expect(storage.damagedCount, 1);
  });

  test(
    'пропавшая папка фрагментов не делает фрагменты повреждёнными',
    () async {
      final id = await put(1);
      final moved = Directory('${dir.path}/moved');
      storage.files.root.renameSync(moved.path);
      now = now.add(const Duration(days: 31));
      final c = checker();
      expect(await c.checkNext(), isNull);
      expect(storage.record(id)!.state, FragmentState.stored);
      moved.renameSync(storage.files.root.path);
      expect((await c.checkNext())!.ok, isTrue);
    },
  );

  test(
    'фоновый цикл проверяет с пределом скорости и останавливается',
    () async {
      for (var i = 1; i <= 3; i++) {
        await put(i);
      }
      now = now.add(const Duration(days: 31));
      final c = IntegrityChecker(
        storage: storage,
        crypto: crypto,
        // Около 200 КБ на фрагмент: три фрагмента — не меньше ~0,4 с.
        bytesPerSecond: 1000000,
        clock: () => now,
      );
      final watch = Stopwatch()..start();
      c.start();
      while (c.checked < 3) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(watch.elapsed, greaterThan(const Duration(milliseconds: 350)));
      await c.stop().timeout(const Duration(seconds: 5));
      expect(c.damaged, 0);
    },
  );
}
