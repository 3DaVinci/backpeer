import 'dart:typed_data';

import 'package:core/src/chunking/chunk_id.dart';
import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/crypto/encrypted_blob.dart';
import 'package:core/src/crypto/secret_bytes.dart';
import 'package:core/src/errors.dart';
import 'package:core/src/util/bytes.dart';

/// Тип чанка в сегменте (data-format.md, раздел 3).
enum ChunkType {
  file(1),
  tree(2);

  new(this.code);

  final int code;

  static ChunkType? fromCode(int code) => switch (code) {
    1 => file,
    2 => tree,
    _ => null,
  };
}

/// Чанк внутри открытого текста сегмента.
final class PackedChunk {
  const new({required this.id, required this.type, required this.data});

  final ChunkId id;
  final ChunkType type;

  /// При разборе — представление внутри открытого текста, без копирования.
  final Uint8List data;
}

/// Открытый текст сегмента: `FSSG`, оглавление по 40 байт, чанки подряд,
/// нули до длины, кратной 64 КиБ, всего не больше 16 МиБ.
abstract final class SegmentPlaintext {
  static const int headerLength = 16;
  static const int entryLength = 40;
  static const int alignment = 65536;
  static const int maxLength = 16 * 1024 * 1024;

  /// Длина открытого текста с выравниванием для чанков с суммарной
  /// длиной [dataLength].
  static int paddedLength(int count, int dataLength) {
    final raw = headerLength + entryLength * count + dataLength;
    return (raw + alignment - 1) ~/ alignment * alignment;
  }

  /// Поместятся ли [count] чанков общей длиной [dataLength].
  static bool fits(int count, int dataLength) =>
      paddedLength(count, dataLength) <= maxLength;

  static Uint8List encode(List<PackedChunk> chunks) {
    if (chunks.isEmpty) throw ArgumentError('Сегмент без чанков');
    final ids = <ChunkId>{};
    var dataLength = 0;
    for (final c in chunks) {
      if (c.data.isEmpty) throw ArgumentError('Пустой чанк');
      if (!ids.add(c.id)) throw ArgumentError('Повтор chunk_id ${c.id}');
      dataLength += c.data.length;
    }
    final total = paddedLength(chunks.length, dataLength);
    if (total > maxLength) {
      throw ArgumentError('Сегмент длиннее $maxLength байт');
    }
    final w = ByteWriter(total)
      ..bytes(_magic)
      ..u8(1)
      ..zeros(3)
      ..u32le(chunks.length)
      ..u32le(dataLength);
    for (final c in chunks) {
      w
        ..bytes(c.id.bytes)
        ..u8(c.type.code)
        ..zeros(3)
        ..u32le(c.data.length);
    }
    for (final c in chunks) {
      w.bytes(c.data);
    }
    w.zeros(total - w.length);
    return w.toBytes();
  }

  /// Разбор с проверками раздела 3. Ошибки — [DataFormatException].
  static List<PackedChunk> parse(Uint8List plain) {
    if (plain.length < alignment ||
        plain.length > maxLength ||
        plain.length % alignment != 0) {
      throw _error(FormatProblem.invalidField, 'длина ${plain.length}');
    }
    final r = ByteReader(plain);
    if (!constantTimeEquals(r.bytes(4), _magic)) {
      throw _error(FormatProblem.badMagic, null, 0);
    }
    final version = r.u8();
    if (version != 1) {
      throw _error(FormatProblem.unsupportedVersion, 'версия $version', 4);
    }
    if (r.u8() != 0 || r.u8() != 0 || r.u8() != 0) {
      throw _error(FormatProblem.reservedNotZero, null, 5);
    }
    final count = r.u32le();
    final dataLength = r.u32le();
    final tocEnd = headerLength + entryLength * count;
    if (count == 0 || tocEnd + dataLength > plain.length) {
      throw _error(FormatProblem.invalidField, 'count $count', 8);
    }
    final entries = <(ChunkId, ChunkType, int)>[];
    final ids = <ChunkId>{};
    var sum = 0;
    for (var i = 0; i < count; i++) {
      final at = r.offset;
      final id = ChunkId(r.bytes(32));
      final code = r.u8();
      final type = ChunkType.fromCode(code);
      if (type == null) {
        throw _error(FormatProblem.unknownType, 'тип $code', at + 32);
      }
      if (r.u8() != 0 || r.u8() != 0 || r.u8() != 0) {
        throw _error(FormatProblem.reservedNotZero, null, at + 33);
      }
      final length = r.u32le();
      if (length == 0) {
        throw _error(FormatProblem.invalidField, 'длина чанка 0', at + 36);
      }
      if (!ids.add(id)) {
        throw _error(FormatProblem.invalidField, 'повтор chunk_id', at);
      }
      sum += length;
      entries.add((id, type, length));
    }
    if (sum != dataLength) {
      throw _error(
        FormatProblem.invalidField,
        'сумма длин $sum, data_length $dataLength',
        12,
      );
    }
    final end = tocEnd + dataLength;
    for (var i = end; i < plain.length; i++) {
      if (plain[i] != 0) {
        throw _error(FormatProblem.invalidField, 'ненулевое выравнивание', i);
      }
    }
    var offset = tocEnd;
    return [
      for (final (id, type, length) in entries)
        PackedChunk(
          id: id,
          type: type,
          data: Uint8List.sublistView(plain, offset, offset += length),
        ),
    ];
  }

  static DataFormatException _error(
    FormatProblem problem, [
    String? detail,
    int? offset,
  ]) => DataFormatException(
    object: 'segment',
    problem: problem,
    detail: detail,
    offset: offset,
  );
}

/// Шифрование открытого текста сегмента в блоб типа 1 и обратно. Ключ —
/// `K_seg(segment_id)`, см. `AccountKeys.segmentKey`.
abstract final class SegmentCipher {
  static Uint8List seal(
    CryptoProvider crypto, {
    required SecretBytes segmentKey,
    required Uint8List segmentId,
    required Uint8List plaintext,
    Uint8List? nonce,
  }) => EncryptedBlob.seal(
    crypto,
    type: BlobType.segment,
    objectId: segmentId,
    key: segmentKey,
    plaintext: plaintext,
    nonce: nonce,
  );

  /// Идентификатор блоба обязан совпасть с [segmentId]
  /// (data-format.md, раздел 5).
  static Uint8List open(
    CryptoProvider crypto, {
    required SecretBytes segmentKey,
    required Uint8List segmentId,
    required Uint8List blob,
  }) => EncryptedBlob.open(
    crypto,
    blob,
    key: segmentKey,
    expectedType: BlobType.segment,
    expectedObjectId: segmentId,
  );
}

final _magic = Uint8List.fromList('FSSG'.codeUnits);
