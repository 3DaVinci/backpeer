// Отпечаток ключей узла для привязки (задачи 6.1.1, 6.1.2; protocol.md,
// раздел 4.17): первые 16 hex-символов BLAKE2b-256(node_id ‖ node_dh),
// группами по 4 через дефис. Вектор фиксирует формат.

import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  late CryptoProvider crypto;
  setUpAll(() async => crypto = await SodiumCryptoProvider.load());

  Uint8List bytes(int value) => Uint8List(32)..fillRange(0, 32, value);

  test('вектор: node_id = 0x11…, node_dh = 0x22…', () {
    expect(
      nodeFingerprint(crypto, nodeId: bytes(0x11), nodeDh: bytes(0x22)),
      '428D-37D6-B34F-605A',
    );
  });

  test('разные ключи дают разный отпечаток', () {
    expect(
      nodeFingerprint(crypto, nodeId: bytes(0x11), nodeDh: bytes(0x22)),
      isNot(nodeFingerprint(crypto, nodeId: bytes(0x11), nodeDh: bytes(0x33))),
    );
  });

  test('формат: 4 группы по 4 символа через дефис', () {
    final fp = nodeFingerprint(
      crypto,
      nodeId: bytes(0x11),
      nodeDh: bytes(0x22),
    );
    expect(fp, matches(RegExp(r'^[0-9A-F]{4}(-[0-9A-F]{4}){3}$')));
  });
}
