// Замер 0.5.2: время Argon2id при разных параметрах (libsodium и hashlib).
// libsodium поддерживает только p = 1, поэтому все замеры с p = 1.
// Тип по умолчанию в hashlib.Argon2 — argon2id.

import 'dart:io';
import 'dart:typed_data';

import 'package:hashlib/hashlib.dart' as hashlib;
import 'package:sodium/sodium_sumo.dart';

Future<void> main() async {
  final sodium = await SodiumSumoInit.init();
  final password = Uint8List.fromList('correct horse battery staple'.codeUnits);
  final salt = Uint8List.fromList(List.generate(16, (i) => i));
  stdout
    ..writeln('| m, МиБ | t | libsodium, мс | hashlib (Dart), мс |')
    ..writeln('|---|---|---|---|');
  for (final (m, t) in const [
    (64, 3),
    (128, 3),
    (256, 3),
    (512, 2),
    (1024, 1),
  ]) {
    final native = _time(() {
      sodium.crypto.pwhash
          .callRaw(
            outLen: 32,
            password: Int8List.fromList(password),
            salt: salt,
            opsLimit: t,
            memLimit: m * 1024 * 1024,
            alg: CryptoPwhashAlgorithm.argon2id13,
          )
          .dispose();
    });
    final dart = _time(() {
      hashlib.Argon2(
        salt: salt,
        iterations: t,
        parallelism: 1,
        memorySizeKB: m * 1024,
      ).convert(password);
    });
    stdout.writeln('| $m | $t | $native | $dart |');
  }
}

int _time(void Function() body) {
  final times = <int>[];
  for (var i = 0; i < 3; i++) {
    final watch = Stopwatch()..start();
    body();
    times.add(watch.elapsedMilliseconds);
  }
  times.sort();
  return times[1];
}
