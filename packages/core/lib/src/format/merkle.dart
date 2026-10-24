import 'dart:typed_data';

import 'package:core/src/crypto/crypto_provider.dart';

/// Размер блока дерева Меркла тела фрагмента: 2^16 байт.
const int merkleBlockLog2 = 16;
const int merkleBlockSize = 1 << merkleBlockLog2;

/// Корень дерева Меркла тела по RFC 6962 (раздел 2.1) с BLAKE2b-256
/// (data-format.md, раздел 5): лист — `H(0x00 || блок)`, узел —
/// `H(0x01 || левый || правый)`, разбиение по наибольшей степени двойки,
/// меньшей числа блоков. Пустое тело не допускается.
Uint8List merkleRoot(CryptoProvider crypto, Uint8List body) =>
    (MerkleBuilder(crypto)..add(body)).finish();

/// Корень дерева тела, которое приходит частями произвольной длины
/// (приём фрагмента узлом, задача 3.2.1): в памяти — неполный блок и
/// хэши листьев, а не тело целиком.
final class MerkleBuilder {
  new(this._crypto);

  final CryptoProvider _crypto;
  final _leafInput = Uint8List(1 + merkleBlockSize);
  final _leaves = <Uint8List>[];
  int _filled = 0;
  int _length = 0;
  bool _finished = false;

  /// Сколько байт тела принято.
  int get length => _length;

  void add(List<int> data) {
    if (_finished) throw StateError('MerkleBuilder уже завершён');
    var offset = 0;
    while (offset < data.length) {
      if (_filled == merkleBlockSize) _flush();
      final take = data.length - offset < merkleBlockSize - _filled
          ? data.length - offset
          : merkleBlockSize - _filled;
      _leafInput.setRange(1 + _filled, 1 + _filled + take, data, offset);
      _filled += take;
      offset += take;
    }
    _length += data.length;
  }

  void _flush() {
    _leaves.add(
      _crypto.blake2b256(Uint8List.sublistView(_leafInput, 0, 1 + _filled)),
    );
    _filled = 0;
  }

  /// Корень; после него [add] недоступен. Пустое тело — [ArgumentError].
  Uint8List finish() {
    if (_finished) throw StateError('MerkleBuilder уже завершён');
    if (_length == 0) throw ArgumentError('Пустое тело фрагмента');
    _finished = true;
    _flush();
    final nodeInput = Uint8List(65)..[0] = 1;
    Uint8List mth(int from, int to) {
      if (to - from == 1) return _leaves[from];
      var split = 1;
      while (split * 2 < to - from) {
        split *= 2;
      }
      final left = mth(from, from + split);
      final right = mth(from + split, to);
      nodeInput
        ..setAll(1, left)
        ..setAll(33, right);
      return _crypto.blake2b256(nodeInput);
    }

    return mth(0, _leaves.length);
  }
}
