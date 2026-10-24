// Общее для фаззеров: настройки из окружения, мутации образцов и прогон
// синхронного разборщика.

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';
import 'package:test_vectors/test_vectors.dart';

final Map<String, String> _env = Platform.environment;
final int fuzzRuns = int.parse(_env['FS_FUZZ_RUNS'] ?? '2000');
final int fuzzSeed = int.parse(_env['FS_FUZZ_SEED'] ?? '1');

/// Время на каждый фаззер вместо числа входов: `FS_FUZZ_SECONDS=600`.
final Duration? fuzzDuration = switch (_env['FS_FUZZ_SECONDS']) {
  final String s => Duration(seconds: int.parse(s)),
  null => null,
};

/// Продолжать ли: [total] прогонов или, если задано, [fuzzDuration].
bool _more(int i, int total, Stopwatch clock) => switch (fuzzDuration) {
  final Duration d => clock.elapsed < d,
  null => i < total,
};

/// Мутация правильного образца: переворот битов, замена байтов на
/// граничные значения, обрезка, удлинение, вставка и удаление участка,
/// перестановка участков; иногда — совсем случайный вход.
Uint8List mutate(Random r, Uint8List sample) {
  if (r.nextInt(20) == 0) {
    return Uint8List.fromList(
      List.generate(r.nextInt(sample.length * 2 + 2), (_) => r.nextInt(256)),
    );
  }
  var b = Uint8List.fromList(sample);
  final steps = 1 + r.nextInt(4);
  for (var s = 0; s < steps; s++) {
    if (b.isEmpty) b = Uint8List(1);
    switch (r.nextInt(8)) {
      case 0:
        b[r.nextInt(b.length)] ^= 1 << r.nextInt(8);
      case 1:
        const interesting = [0, 1, 0x7F, 0x80, 0xFF];
        b[r.nextInt(b.length)] = interesting[r.nextInt(interesting.length)];
      case 2:
        // Граничное 32-битное число по случайному смещению: длины и
        // счётчики в заголовках — u32le.
        if (b.length >= 4) {
          const values = [0, 1, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF, 65536];
          final at = r.nextInt(b.length - 3);
          final v = values[r.nextInt(values.length)];
          for (var i = 0; i < 4; i++) {
            b[at + i] = (v >> (8 * i)) & 0xFF;
          }
        }
      case 3:
        b = Uint8List.sublistView(b, 0, r.nextInt(b.length + 1));
      case 4:
        b = Uint8List.fromList([
          ...b,
          ...List.generate(1 + r.nextInt(64), (_) => r.nextInt(256)),
        ]);
      case 5:
        final at = r.nextInt(b.length + 1);
        b = Uint8List.fromList([
          ...b.sublist(0, at),
          ...List.generate(1 + r.nextInt(16), (_) => r.nextInt(256)),
          ...b.sublist(at),
        ]);
      case 6:
        final at = r.nextInt(b.length);
        final end = min(b.length, at + 1 + r.nextInt(16));
        b = Uint8List.fromList([...b.sublist(0, at), ...b.sublist(end)]);
      default:
        final a = r.nextInt(b.length);
        final c = r.nextInt(b.length);
        final len = min(16, min(b.length - a, b.length - c));
        b.setRange(c, c + len, Uint8List.fromList(b.sublist(a, a + len)));
    }
  }
  return b;
}

/// [fuzzRuns] мутаций каждого из [samples] через [target]. Допустимы только
/// успех и [CoreException]. Возвращает число отказов.
int fuzz(
  String name,
  List<Uint8List> samples,
  void Function(Uint8List input) target, {
  int? runs,
}) {
  final r = Random(fuzzSeed ^ name.hashCode);
  var rejected = 0;
  final total = runs ?? fuzzRuns;
  final clock = Stopwatch()..start();
  for (var i = 0; _more(i, total, clock); i++) {
    final input = mutate(r, samples[i % samples.length]);
    try {
      target(input);
    } on CoreException {
      rejected++;
    } on Object catch (e, st) {
      fail(
        '$name: seed $fuzzSeed, прогон $i, вход ${input.length} байт '
        '${toHex(input.take(256).toList())}…\n$e\n$st',
      );
    }
  }
  return rejected;
}

/// Асинхронный вариант [fuzz]: каждый прогон обязан завершиться за
/// [hang], иначе это зависание.
Future<int> fuzzAsync(
  String name,
  List<Uint8List> samples,
  Future<void> Function(Uint8List input) target, {
  int? runs,
  Duration hang = const Duration(seconds: 10),
}) async {
  final r = Random(fuzzSeed ^ name.hashCode);
  var rejected = 0;
  final total = runs ?? fuzzRuns;
  final clock = Stopwatch()..start();
  for (var i = 0; _more(i, total, clock); i++) {
    final input = mutate(r, samples[i % samples.length]);
    String where() =>
        '$name: seed $fuzzSeed, прогон $i, вход ${input.length} байт '
        '${toHex(input.take(256).toList())}…';
    try {
      await target(input).timeout(hang);
    } on CoreException {
      rejected++;
    } on TimeoutException {
      fail('${where()}\nзависание дольше $hang');
    } on Object catch (e, st) {
      fail('${where()}\n$e\n$st');
    }
  }
  return rejected;
}
