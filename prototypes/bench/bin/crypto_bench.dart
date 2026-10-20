// Замеры 0.5.1 и 0.5.2: скорость AEAD, хэшей и Argon2id в чистом Dart
// (пакеты cryptography, hashlib, crypto) и через libsodium (пакет sodium).
//
//   dart run bench:crypto_bench            # JIT
//   dart build cli -t bin/crypto_bench.dart # AOT, как у демона
//
// Вывод — строки таблицы Markdown для docs/benchmarks.md.

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as dart_crypto;
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:hashlib/hashlib.dart' as hashlib;
import 'package:sodium/sodium_sumo.dart';

const int _bufferSize = 16 * 1024 * 1024; // размер сегмента
const _minDuration = Duration(seconds: 2);

Future<void> main(List<String> arguments) async {
  final skipArgon = arguments.contains('--no-argon2');
  final data = Uint8List(_bufferSize);
  for (var i = 0; i < data.length; i++) {
    data[i] = (i * 2654435761) >> 13;
  }
  final key = Uint8List.fromList(List.generate(32, (i) => i));
  final nonce24 = Uint8List.fromList(List.generate(24, (i) => i));
  final nonce12 = Uint8List.fromList(List.generate(12, (i) => i));

  stdout
    ..writeln('# ${Platform.operatingSystem} ${Platform.version}')
    ..writeln('# CPU: ${_cpuName()}, буфер ${_bufferSize >> 20} МиБ')
    ..writeln('| Операция | Реализация | МБ/с |')
    ..writeln('|---|---|---|');

  // --- AEAD ---
  const xchacha = DartXchacha20.poly1305Aead();
  final secretKey = SecretKey(key);
  await _throughput('XChaCha20-Poly1305', 'cryptography (Dart)', () async {
    await xchacha.encrypt(data, secretKey: secretKey, nonce: nonce24);
  });
  final aesGcm = DartAesGcm.with256bits();
  await _throughput('AES-256-GCM', 'cryptography (Dart)', () async {
    await aesGcm.encrypt(data, secretKey: secretKey, nonce: nonce12);
  });

  SodiumSumo? sodium;
  try {
    sodium = await SodiumSumoInit.init();
  } on Object catch (e) {
    stdout.writeln('| — | libsodium недоступен: $e | — |');
  }
  if (sodium != null) {
    final aead = sodium.crypto.aeadXChaCha20Poly1305IETF;
    final sodiumKey = SecureKey.fromList(sodium, key);
    await _throughput('XChaCha20-Poly1305', 'libsodium (FFI)', () async {
      aead.encrypt(message: data, nonce: nonce24, key: sodiumKey);
    });
  }

  // --- Хэши ---
  await _throughput('SHA-256', 'crypto (Dart)', () async {
    dart_crypto.sha256.convert(data);
  });
  await _throughput('SHA-256', 'cryptography (Dart)', () async {
    await const DartSha256().hash(data);
  });
  await _throughput('SHA-256', 'hashlib (Dart)', () async {
    hashlib.sha256.convert(data);
  });
  await _throughput('BLAKE2b-256', 'hashlib (Dart)', () async {
    hashlib.blake2b256.convert(data);
  });
  await _throughput('BLAKE2b-512', 'cryptography (Dart)', () async {
    await const DartBlake2b().hash(data);
  });
  if (sodium != null) {
    final hash = sodium.crypto.genericHash;
    await _throughput('BLAKE2b-256', 'libsodium (FFI)', () async {
      hash(message: data, outLen: 32);
    });
  }

  if (skipArgon) return;

  // --- Argon2id: 64 МиБ, 3 прохода, 1 поток ---
  stdout
    ..writeln()
    ..writeln('| Argon2id (m=64 МиБ, t=3, p=1) | Реализация | мс |')
    ..writeln('|---|---|---|');
  final password = Uint8List.fromList('correct horse battery staple'.codeUnits);
  final salt = Uint8List.fromList(List.generate(16, (i) => i));
  await _latency('Argon2id', 'cryptography (Dart)', () async {
    await const DartArgon2id(
      parallelism: 1,
      memory: 65536,
      iterations: 3,
      hashLength: 32,
    ).deriveKey(secretKey: SecretKey(password), nonce: salt);
  });
  await _latency('Argon2id', 'hashlib (Dart)', () async {
    hashlib.Argon2(
      salt: salt,
      hashLength: 32,
      iterations: 3,
      parallelism: 1,
      memorySizeKB: 65536,
    ).convert(password);
  });
  if (sodium != null) {
    final pwhash = sodium.crypto.pwhash;
    await _latency('Argon2id', 'libsodium (FFI)', () async {
      pwhash.callRaw(
        outLen: 32,
        password: Int8List.fromList(password),
        salt: salt,
        opsLimit: 3,
        memLimit: 64 * 1024 * 1024,
        alg: CryptoPwhashAlgorithm.argon2id13,
      );
    });
  }
}

Future<void> _throughput(
  String operation,
  String implementation,
  Future<void> Function() body,
) async {
  await body(); // прогрев
  final watch = Stopwatch()..start();
  var runs = 0;
  while (watch.elapsed < _minDuration) {
    await body();
    runs++;
  }
  final mbPerSecond =
      runs * _bufferSize / 1e6 / (watch.elapsedMicroseconds / 1e6);
  stdout.writeln(
    '| $operation | $implementation | ${mbPerSecond.toStringAsFixed(1)} |',
  );
}

Future<void> _latency(
  String operation,
  String implementation,
  Future<void> Function() body,
) async {
  await body(); // прогрев
  final times = <int>[];
  for (var i = 0; i < 3; i++) {
    final watch = Stopwatch()..start();
    await body();
    times.add(watch.elapsedMilliseconds);
  }
  times.sort();
  stdout.writeln('| $operation | $implementation | ${times[1]} |');
}

String _cpuName() {
  try {
    final line = File('/proc/cpuinfo')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('model name'));
    return line.split(':').last.trim();
  } on Object {
    return 'неизвестно';
  }
}
