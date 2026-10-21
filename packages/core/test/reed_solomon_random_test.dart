// Случайные тесты Reed–Solomon с фиксированным seed: упавший прогон
// воспроизводится по seed из сообщения.

import 'dart:math';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:core/src/erasure/galois8.dart';
import 'package:test/test.dart';

const _seed = 20261021;

List<Uint8List> _encoded(ReedSolomon rs, Random random, int length) {
  final shards = [
    for (var i = 0; i < rs.totalShards; i++)
      Uint8List.fromList(
        i < rs.dataShards
            ? List.generate(length, (_) => random.nextInt(256))
            : List.filled(length, 0),
      ),
  ];
  rs.encode(shards);
  return shards;
}

void _expectRestores(
  ReedSolomon rs,
  List<Uint8List> full,
  Set<int> erased,
  String reason,
) {
  final shards = <Uint8List?>[
    for (var i = 0; i < full.length; i++)
      if (erased.contains(i)) null else Uint8List.fromList(full[i]),
  ];
  rs.reconstruct(shards);
  for (var i = 0; i < full.length; i++) {
    expect(shards[i], full[i], reason: '$reason, фрагмент $i');
  }
}

void main() {
  group('поле GF(2^8)', () {
    test('аксиомы на всех парах и случайных тройках', () {
      for (var a = 0; a < 256; a++) {
        expect(Galois8.mul(a, 1), a);
        expect(Galois8.mul(a, 0), 0);
        for (var b = 0; b < 256; b++) {
          expect(Galois8.mul(a, b), Galois8.mul(b, a));
          if (b != 0) expect(Galois8.mul(Galois8.div(a, b), b), a);
        }
      }
      final random = Random(_seed);
      for (var i = 0; i < 20000; i++) {
        final a = random.nextInt(256);
        final b = random.nextInt(256);
        final c = random.nextInt(256);
        expect(
          Galois8.mul(Galois8.mul(a, b), c),
          Galois8.mul(a, Galois8.mul(b, c)),
        );
        expect(Galois8.mul(a, b ^ c), Galois8.mul(a, b) ^ Galois8.mul(a, c));
      }
    });

    test('2 — образующий элемент: степени дают все 255 ненулевых', () {
      final powers = {for (var i = 0; i < 255; i++) Galois8.pow(2, i)};
      expect(powers, hasLength(255));
      expect(powers.contains(0), isFalse);
    });

    test('деление на ноль — ошибка', () {
      expect(() => Galois8.div(1, 0), throwsArgumentError);
    });
  });

  group('восстановление из любых k из n (seed $_seed)', () {
    final random = Random(_seed);
    const shapes = [
      (1, 2),
      (2, 3),
      (4, 6),
      (10, 16),
      (10, 20),
      (17, 31),
      (64, 96),
    ];
    for (final (k, n) in shapes) {
      test('k=$k, n=$n', () {
        final rs = ReedSolomon(k, n - k);
        for (var round = 0; round < 25; round++) {
          final length = 1 + random.nextInt(300);
          final full = _encoded(rs, random, length);
          final order = List.generate(n, (i) => i)..shuffle(random);
          final lost = random.nextInt(n - k + 1);
          _expectRestores(
            rs,
            full,
            order.take(lost).toSet(),
            'раунд $round, потеряны ${order.take(lost).toList()}',
          );
        }
      });
    }
  });

  group('особые случаи (10 из 20)', () {
    final rs = ReedSolomon(10, 10);
    final full = _encoded(rs, Random(_seed + 1), 1000);

    test('нет потерь — фрагменты не меняются', () {
      _expectRestores(rs, full, {}, 'без потерь');
    });

    test('потеряны только данные', () {
      _expectRestores(rs, full, {0, 3, 5, 7, 8, 9}, 'данные');
      _expectRestores(rs, full, {for (var i = 0; i < 10; i++) i}, 'все данные');
    });

    test('потеряна только чётность', () {
      _expectRestores(rs, full, {10, 15, 19}, 'чётность');
      _expectRestores(rs, full, {for (var i = 10; i < 20; i++) i}, 'вся');
    });

    test('потеряно n − k + 1 — InsufficientShardsException', () {
      final shards = <Uint8List?>[
        for (var i = 0; i < 20; i++)
          if (i < 11) null else full[i],
      ];
      expect(
        () => rs.reconstruct(shards),
        throwsA(isA<InsufficientShardsException>()),
      );
    });
  });

  group('кеш обратных матриц', () {
    test(
      'повтор набора не добавляет записей; только чётность — без матрицы',
      () {
        final rs = ReedSolomon(4, 4);
        final full = _encoded(rs, Random(_seed + 2), 64);
        _expectRestores(rs, full, {4, 5}, 'чётность');
        expect(rs.cachedDecodeMatrices, 0);
        _expectRestores(rs, full, {0, 1}, 'первый раз');
        _expectRestores(rs, full, {0, 1}, 'из кеша');
        expect(rs.cachedDecodeMatrices, 1);
        _expectRestores(rs, full, {0, 2}, 'другой набор');
        expect(rs.cachedDecodeMatrices, 2);
      },
    );

    test('ограничен по размеру и даёт верный результат после вытеснения', () {
      final rs = ReedSolomon(3, 7);
      final full = _encoded(rs, Random(_seed + 3), 32);
      // Наборы «первых k имеющихся» — все 3-подмножества из 10 (120 штук),
      // меньше ёмкости; прогоняем дважды, затем ещё раз с данными.
      for (var round = 0; round < 2; round++) {
        for (var a = 0; a < 10; a++) {
          for (var b = a + 1; b < 10; b++) {
            for (var c = b + 1; c < 10; c++) {
              final erased = {
                for (var i = 0; i < 10; i++)
                  if (i != a && i != b && i != c) i,
              };
              _expectRestores(rs, full, erased, '$a,$b,$c');
            }
          }
        }
      }
      expect(
        rs.cachedDecodeMatrices,
        lessThanOrEqualTo(ReedSolomon.decodeCacheCapacity),
      );
    });
  });
}
