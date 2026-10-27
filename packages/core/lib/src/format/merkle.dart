import 'dart:typed_data';

import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/util/bytes.dart';

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

  /// Хэши листьев `H(0x00 || блок)` подряд, по 32 байта; доступны после
  /// [finish]. Узел хранит их рядом с фрагментом, чтобы отвечать на аудит,
  /// читая один блок (задача 4.1.2).
  Uint8List get leaves {
    if (!_finished) throw StateError('MerkleBuilder не завершён');
    final out = Uint8List(32 * _leaves.length);
    for (var i = 0; i < _leaves.length; i++) {
      out.setAll(32 * i, _leaves[i]);
    }
    return out;
  }

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
    return _subtreeRoot(_crypto, _leaves, 0, _leaves.length);
  }
}

/// Число блоков (листьев) тела длины [bodyLength].
int merkleLeafCount(int bodyLength) =>
    (bodyLength + merkleBlockSize - 1) >> merkleBlockLog2;

/// Хэш листа: `H(0x00 || блок)`.
Uint8List merkleLeafHash(CryptoProvider crypto, List<int> block) =>
    crypto.blake2b256(Uint8List(1 + block.length)..setAll(1, block));

/// Хэши листьев [leaves] (по 32 байта подряд, [MerkleBuilder.leaves]) →
/// список.
List<Uint8List> splitMerkleLeaves(Uint8List leaves) {
  if (leaves.isEmpty || leaves.length % 32 != 0) {
    throw ArgumentError('хэши листьев: по 32 байта, хотя бы один');
  }
  return [
    for (var i = 0; i < leaves.length; i += 32)
      Uint8List.sublistView(leaves, i, i + 32),
  ];
}

/// Корень дерева по хэшам листьев.
Uint8List merkleRootOfLeaves(CryptoProvider crypto, List<Uint8List> leaves) {
  if (leaves.isEmpty) throw ArgumentError('Пустое тело фрагмента');
  return _subtreeRoot(crypto, leaves, 0, leaves.length);
}

/// Путь аудита к листу [index] по RFC 6962 (раздел 2.1.1, `PATH(m, D[n])`):
/// хэши соседних поддеревьев от листа к корню (protocol.md, раздел 4.13).
/// У дерева из одного листа путь пустой.
List<Uint8List> merkleAuditPath(
  CryptoProvider crypto,
  List<Uint8List> leaves,
  int index,
) {
  if (index < 0 || index >= leaves.length) {
    throw RangeError.range(index, 0, leaves.length - 1, 'index');
  }
  final path = <Uint8List>[];
  void walk(int m, int from, int to) {
    if (to - from == 1) return;
    final split = _split(to - from);
    if (m < split) {
      walk(m, from, from + split);
      path.add(_subtreeRoot(crypto, leaves, from + split, to));
    } else {
      walk(m - split, from + split, to);
      path.add(_subtreeRoot(crypto, leaves, from, from + split));
    }
  }

  walk(index, 0, leaves.length);
  return path;
}

/// Проверка пути аудита по RFC 9162 (раздел 2.1.3.2): блок [block] с
/// номером [index] в дереве из [leafCount] листьев с путём [path] даёт
/// корень [root]. Длину блока проверяет вызывающий
/// ([merkleBlockLength]).
bool verifyMerkleAuditPath(
  CryptoProvider crypto, {
  required Uint8List root,
  required int leafCount,
  required int index,
  required List<int> block,
  required List<List<int>> path,
}) {
  if (index < 0 || index >= leafCount || root.length != 32) return false;
  var fn = index;
  var sn = leafCount - 1;
  var r = merkleLeafHash(crypto, block);
  final input = Uint8List(65)..[0] = 1;
  for (final p in path) {
    if (p.length != 32 || sn == 0) return false;
    if (fn.isOdd || fn == sn) {
      input
        ..setAll(1, p)
        ..setAll(33, r);
      r = crypto.blake2b256(input);
      if (fn.isEven) {
        while (fn.isEven && fn != 0) {
          fn >>= 1;
          sn >>= 1;
        }
      }
    } else {
      input
        ..setAll(1, r)
        ..setAll(33, p);
      r = crypto.blake2b256(input);
    }
    fn >>= 1;
    sn >>= 1;
  }
  return sn == 0 && constantTimeEquals(r, root);
}

/// Длина блока [index] тела длины [bodyLength]: 64 КиБ, последний — остаток.
int merkleBlockLength(int bodyLength, int index) {
  final start = index << merkleBlockLog2;
  final rest = bodyLength - start;
  return rest < merkleBlockSize ? rest : merkleBlockSize;
}

/// Наибольшая степень двойки, меньшая [n] (n ≥ 2).
int _split(int n) {
  var split = 1;
  while (split * 2 < n) {
    split *= 2;
  }
  return split;
}

Uint8List _subtreeRoot(
  CryptoProvider crypto,
  List<Uint8List> leaves,
  int from,
  int to,
) {
  if (to - from == 1) return leaves[from];
  final split = _split(to - from);
  final left = _subtreeRoot(crypto, leaves, from, from + split);
  final right = _subtreeRoot(crypto, leaves, from + split, to);
  return crypto.blake2b256(
    Uint8List(65)
      ..[0] = 1
      ..setAll(1, left)
      ..setAll(33, right),
  );
}
