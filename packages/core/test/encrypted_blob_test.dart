import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';
import 'package:test_vectors/test_vectors.dart';

void main() {
  late CryptoProvider crypto;
  setUpAll(() async => crypto = await SodiumCryptoProvider.load());

  group('blob', () {
    for (final c in vectorCases(loadVectors('crypto/blob.json'))) {
      final input = c['input']! as Map<String, Object?>;
      final expected = c['expected']! as Map<String, Object?>;
      test(c['name'], () {
        final key = SecretBytes(hexToBytes(input['key']! as String));
        if (expected.containsKey('error')) {
          final blob = hexToBytes(input['blob']! as String);
          final matcher = switch (expected['error']) {
            'format' => isA<DataFormatException>(),
            'integrity' => isA<IntegrityException>(),
            final e => throw StateError('Неизвестный вид ошибки $e'),
          };
          expect(
            () => EncryptedBlob.open(crypto, blob, key: key),
            throwsA(matcher),
          );
          return;
        }
        final plaintext = input.containsKey('plaintextPattern')
            ? patternBytes(input['plaintextPattern']! as Map<String, Object?>)
            : hexToBytes(input['plaintext']! as String);
        final type = BlobType.fromCode(input['type']! as int)!;
        final objectId = hexToBytes(input['objectId']! as String);
        final blob = EncryptedBlob.seal(
          crypto,
          type: type,
          objectId: objectId,
          key: key,
          plaintext: plaintext,
          nonce: hexToBytes(input['nonce']! as String),
        );
        expect(bytesToHex(blob), expected['blob']);
        expect(
          EncryptedBlob.open(
            crypto,
            blob,
            key: key,
            expectedType: type,
            expectedObjectId: objectId,
          ),
          plaintext,
        );
        final header = BlobHeader.parse(blob);
        expect(header.type, type);
        expect(header.objectId, objectId);
      });
    }
  });

  group('подмена целого блоба', () {
    final key = SecretBytes(Uint8List(32));
    final id = Uint8List.fromList(List.filled(32, 1));
    late Uint8List blob;
    setUp(() {
      blob = EncryptedBlob.seal(
        crypto,
        type: BlobType.snapshot,
        objectId: id,
        key: key,
        plaintext: Uint8List(10),
      );
    });

    test('не тот тип — format', () {
      expect(
        () => EncryptedBlob.open(
          crypto,
          blob,
          key: key,
          expectedType: BlobType.indexObject,
        ),
        throwsA(isA<DataFormatException>()),
      );
    });

    test('не тот идентификатор — integrity', () {
      expect(
        () => EncryptedBlob.open(
          crypto,
          blob,
          key: key,
          expectedObjectId: Uint8List(32),
        ),
        throwsA(
          isA<IntegrityException>().having(
            (e) => e.check,
            'check',
            IntegrityCheck.objectId,
          ),
        ),
      );
    });

    test('чужой ключ — integrity', () {
      expect(
        () => EncryptedBlob.open(
          crypto,
          blob,
          key: SecretBytes(Uint8List(32)..[0] = 1),
        ),
        throwsA(isA<IntegrityException>()),
      );
    });
  });

  test('случайный nonce при каждом seal', () {
    final key = SecretBytes(Uint8List(32));
    Uint8List seal() => EncryptedBlob.seal(
      crypto,
      type: BlobType.segment,
      objectId: Uint8List(32),
      key: key,
      plaintext: Uint8List(0),
    );
    expect(
      BlobHeader.parse(seal()).nonce,
      isNot(BlobHeader.parse(seal()).nonce),
    );
    expect(seal().length, EncryptedBlob.overhead);
  });
}
