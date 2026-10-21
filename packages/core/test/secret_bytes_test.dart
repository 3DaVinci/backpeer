import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  test('SecretBytes копирует вход и не показывает содержимое', () {
    final source = [1, 2, 3];
    final secret = SecretBytes(source);
    source[0] = 9;
    expect(secret.bytes, [1, 2, 3]);
    expect(secret.toString(), 'SecretBytes(3 байт)');
    expect('$secret', isNot(contains('1, 2')));
  });

  test('adopt не копирует, dispose затирает', () {
    final buffer = Uint8List.fromList([5, 6]);
    final secret = SecretBytes.adopt(buffer)..dispose();
    expect(buffer, [0, 0]);
    expect(secret.isDisposed, isTrue);
    expect(() => secret.bytes, throwsStateError);
  });

  test('Argon2Params по умолчанию — из crypto.md', () {
    const params = Argon2Params();
    expect(params.memoryKiB, 262144);
    expect(params.iterations, 3);
    expect(params.parallelism, 1);
  });
}
