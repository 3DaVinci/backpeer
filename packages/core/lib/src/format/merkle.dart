import 'dart:typed_data';

import 'package:core/src/crypto/crypto_provider.dart';

/// Размер блока дерева Меркла тела фрагмента: 2^16 байт.
const int merkleBlockLog2 = 16;
const int merkleBlockSize = 1 << merkleBlockLog2;

/// Корень дерева Меркла тела по RFC 6962 (раздел 2.1) с BLAKE2b-256
/// (data-format.md, раздел 5): лист — `H(0x00 || блок)`, узел —
/// `H(0x01 || левый || правый)`, разбиение по наибольшей степени двойки,
/// меньшей числа блоков. Пустое тело не допускается.
Uint8List merkleRoot(CryptoProvider crypto, Uint8List body) {
  if (body.isEmpty) throw ArgumentError('Пустое тело фрагмента');
  final blocks = (body.length + merkleBlockSize - 1) >> merkleBlockLog2;
  final leafInput = Uint8List(1 + merkleBlockSize);
  final leaves = <Uint8List>[
    for (var b = 0; b < blocks; b++)
      () {
        final start = b * merkleBlockSize;
        final end = start + merkleBlockSize < body.length
            ? start + merkleBlockSize
            : body.length;
        leafInput.setRange(1, 1 + end - start, body, start);
        return crypto.blake2b256(
          Uint8List.sublistView(leafInput, 0, 1 + end - start),
        );
      }(),
  ];
  final nodeInput = Uint8List(65)..[0] = 1;
  Uint8List mth(int from, int to) {
    if (to - from == 1) return leaves[from];
    var split = 1;
    while (split * 2 < to - from) {
      split *= 2;
    }
    final left = mth(from, from + split);
    final right = mth(from + split, to);
    nodeInput
      ..setAll(1, left)
      ..setAll(33, right);
    return crypto.blake2b256(nodeInput);
  }

  return mth(0, blocks);
}
