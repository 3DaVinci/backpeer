import 'dart:typed_data';

import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/erasure/erasure_coder.dart';
import 'package:core/src/erasure/reed_solomon.dart';
import 'package:core/src/errors.dart';
import 'package:core/src/format/merkle.dart';
import 'package:core/src/util/bytes.dart';

/// `shard_size = округлить_вверх(⌈L / k⌉, 64)` (data-format.md, раздел 4).
int shardSizeFor(int blobLength, int k) {
  final per = (blobLength + k - 1) ~/ k;
  return (per + 63) ~/ 64 * 64;
}

/// Проверка параметров кода: `1 ≤ k < n ≤ 255`.
void checkCodeParameters(int k, int n) {
  if (k < 1 || k >= n || n > 255) {
    throw ArgumentError('Нужно 1 ≤ k < n ≤ 255; получено k=$k, n=$n');
  }
}

/// Заголовок фрагмента, 96 байт (data-format.md, раздел 5).
final class FragmentHeader {
  const new({
    required this.k,
    required this.n,
    required this.index,
    required this.blobLength,
    required this.shardSize,
    required this.segmentId,
    required this.bodyRoot,
  });

  /// Разбор с проверкой полей. Ошибки — [DataFormatException].
  factory parse(Uint8List bytes) {
    if (bytes.length < length) {
      throw _error(FormatProblem.truncated, '${bytes.length} байт');
    }
    final r = ByteReader(bytes);
    if (!constantTimeEquals(r.bytes(4), _magic)) {
      throw _error(FormatProblem.badMagic, null, 0);
    }
    final version = r.u8();
    if (version != 1) {
      throw _error(FormatProblem.unsupportedVersion, 'версия $version', 4);
    }
    final scheme = r.u8();
    if (scheme != schemeReedSolomon) {
      throw _error(FormatProblem.unknownType, 'схема $scheme', 5);
    }
    final k = r.u8();
    final n = r.u8();
    final index = r.u8();
    if (k < 1 || k >= n || index >= n) {
      throw _error(FormatProblem.invalidField, 'k=$k, n=$n, index=$index', 6);
    }
    final log2 = r.u8();
    if (log2 != merkleBlockLog2) {
      throw _error(FormatProblem.invalidField, 'log2 блока $log2', 9);
    }
    if (r.u16le() != 0) throw _error(FormatProblem.reservedNotZero, null, 10);
    final blobLength = r.u32le();
    final shardSize = r.u32le();
    if (blobLength == 0 || shardSize != shardSizeFor(blobLength, k)) {
      throw _error(
        FormatProblem.invalidField,
        'shard_size $shardSize при blob_length $blobLength и k=$k',
        12,
      );
    }
    final segmentId = Uint8List.fromList(r.bytes(32));
    final bodyRoot = Uint8List.fromList(r.bytes(32));
    for (final b in r.bytes(12)) {
      if (b != 0) throw _error(FormatProblem.reservedNotZero, null, 84);
    }
    return FragmentHeader(
      k: k,
      n: n,
      index: index,
      blobLength: blobLength,
      shardSize: shardSize,
      segmentId: segmentId,
      bodyRoot: bodyRoot,
    );
  }

  static const int length = 96;
  static const int schemeReedSolomon = 1;

  final int k;
  final int n;
  final int index;
  final int blobLength;
  final int shardSize;
  final Uint8List segmentId;
  final Uint8List bodyRoot;

  Uint8List toBytes() =>
      (ByteWriter(length)
            ..bytes(_magic)
            ..u8(1)
            ..u8(schemeReedSolomon)
            ..u8(k)
            ..u8(n)
            ..u8(index)
            ..u8(merkleBlockLog2)
            ..u16le(0)
            ..u32le(blobLength)
            ..u32le(shardSize)
            ..bytes(segmentId)
            ..bytes(bodyRoot)
            ..zeros(12))
          .toBytes();

  /// `fragment_id = H(заголовок)`.
  Uint8List fragmentId(CryptoProvider crypto) => crypto.blake2b256(toBytes());

  /// Тот же сегмент и те же параметры кода.
  bool sameSegment(FragmentHeader other) =>
      k == other.k &&
      n == other.n &&
      blobLength == other.blobLength &&
      shardSize == other.shardSize &&
      constantTimeEquals(segmentId, other.segmentId);
}

/// Фрагмент: заголовок и тело `shard_size` байт.
final class Fragment {
  const new(this.header, this.body) : _bytes = null;

  /// Фрагмент, уже собранный в одном буфере (заголовок и тело подряд):
  /// [toBytes] отдаёт его без копирования.
  const new _assembled(this.header, this.body, this._bytes);

  /// Разбор: заголовок и длина тела. Ошибки — [DataFormatException]. Корень
  /// Меркла и идентификатор проверяет [verify].
  factory parse(Uint8List bytes) {
    final header = FragmentHeader.parse(bytes);
    final bodyLength = bytes.length - FragmentHeader.length;
    if (bodyLength != header.shardSize) {
      throw _error(
        bodyLength < header.shardSize
            ? FormatProblem.truncated
            : FormatProblem.tooLarge,
        'тело $bodyLength байт, shard_size ${header.shardSize}',
        FragmentHeader.length,
      );
    }
    return Fragment._assembled(
      header,
      Uint8List.sublistView(bytes, FragmentHeader.length),
      bytes,
    );
  }

  final FragmentHeader header;
  final Uint8List body;
  final Uint8List? _bytes;

  /// Заголовок и тело подряд, новая копия.
  Uint8List toBytes() => Uint8List(FragmentHeader.length + body.length)
    ..setAll(0, header.toBytes())
    ..setAll(FragmentHeader.length, body);

  /// Заголовок и тело подряд без копирования, если фрагмент уже собран в
  /// одном буфере (после [encodeFragments] или [Fragment.parse]); иначе —
  /// копия. Буфер общий с фрагментом: не изменять.
  Uint8List get bytes => _bytes ?? toBytes();

  /// Проверка целостности (data-format.md, раздел 5, шаги 2–3): корень
  /// дерева тела и, если задан, ожидаемый `fragment_id` (по индексу или
  /// талону). Расхождение — [IntegrityException].
  void verify(CryptoProvider crypto, {Uint8List? expectedFragmentId}) {
    if (!constantTimeEquals(merkleRoot(crypto, body), header.bodyRoot)) {
      throw IntegrityException(
        object: 'fragment',
        check: IntegrityCheck.merkleRoot,
        objectId: header.segmentId,
      );
    }
    if (expectedFragmentId != null &&
        !constantTimeEquals(header.fragmentId(crypto), expectedFragmentId)) {
      throw IntegrityException(
        object: 'fragment',
        check: IntegrityCheck.fragmentId,
        objectId: header.segmentId,
      );
    }
  }
}

/// Блоб сегмента → n фрагментов (data-format.md, разделы 4–5).
List<Fragment> encodeFragments(
  CryptoProvider crypto, {
  required Uint8List blob,
  required Uint8List segmentId,
  required int k,
  required int n,
  ErasureCoder? coder,
}) {
  checkCodeParameters(k, n);
  if (blob.isEmpty) throw ArgumentError('Пустой блоб');
  if (segmentId.length != 32) throw ArgumentError('segment_id — 32 байта');
  final rs = coder ?? ReedSolomon(k, n - k);
  if (rs.dataShards != k || rs.totalShards != n) {
    throw ArgumentError('ErasureCoder для других k и n');
  }
  final size = shardSizeFor(blob.length, k);
  // Каждый фрагмент сразу в своём буфере «заголовок + тело»: Reed–Solomon
  // пишет прямо в тела, лишних копий нет. Смещение тела 96 кратно 8, так
  // что быстрый путь на словах u64 сохраняется.
  const h = FragmentHeader.length;
  final buffers = [for (var i = 0; i < n; i++) Uint8List(h + size)];
  final shards = [for (final b in buffers) Uint8List.sublistView(b, h)];
  for (var i = 0, offset = 0; i < k && offset < blob.length; i++) {
    final take = blob.length - offset < size ? blob.length - offset : size;
    shards[i].setRange(0, take, blob, offset);
    offset += take;
  }
  rs.encode(shards);
  return [
    for (var i = 0; i < n; i++)
      () {
        final header = FragmentHeader(
          k: k,
          n: n,
          index: i,
          blobLength: blob.length,
          shardSize: size,
          segmentId: Uint8List.fromList(segmentId),
          bodyRoot: merkleRoot(crypto, shards[i]),
        );
        buffers[i].setAll(0, header.toBytes());
        return Fragment._assembled(header, shards[i], buffers[i]);
      }(),
  ];
}

/// Любые k (или больше) фрагментов одного сегмента → блоб. Каждый
/// фрагмент проверяется ([Fragment.verify]); [expectedFragmentIds] — по
/// номерам, из индекса. Чужой сегмент или другие параметры —
/// [IntegrityException]; повтор номера и нехватка —
/// [InsufficientShardsException].
///
/// [verified] — фрагменты уже проверены вызывающим ([Fragment.verify] при
/// чтении): дерево Меркла не считается второй раз. Проверка сегмента,
/// параметров и номеров остаётся.
Uint8List decodeFragments(
  CryptoProvider crypto,
  List<Fragment> fragments, {
  required Uint8List segmentId,
  Map<int, Uint8List>? expectedFragmentIds,
  ErasureCoder? coder,
  bool verified = false,
}) {
  if (fragments.isEmpty) {
    throw const InsufficientShardsException(available: 0, required: 1);
  }
  final first = fragments.first.header;
  final shards = List<Uint8List?>.filled(first.n, null);
  var present = 0;
  for (final f in fragments) {
    final h = f.header;
    if (!constantTimeEquals(h.segmentId, segmentId) || !h.sameSegment(first)) {
      throw IntegrityException(
        object: 'fragment',
        check: IntegrityCheck.objectId,
        objectId: h.segmentId,
      );
    }
    if (!verified) {
      f.verify(crypto, expectedFragmentId: expectedFragmentIds?[h.index]);
    }
    if (shards[h.index] == null) {
      shards[h.index] = f.body;
      present++;
    }
  }
  if (present < first.k) {
    throw InsufficientShardsException(
      available: present,
      required: first.k,
      segmentId: segmentId,
    );
  }
  final rs = coder ?? ReedSolomon(first.k, first.n - first.k);
  final missingData = [
    for (var i = 0; i < first.k; i++)
      if (shards[i] == null) i,
  ];
  if (missingData.isNotEmpty) {
    // reconstruct не меняет имеющиеся буферы, только заполняет пустые места.
    final work = List<Uint8List?>.of(shards);
    rs.reconstruct(work);
    for (final i in missingData) {
      shards[i] = work[i];
    }
  }
  final blob = Uint8List(first.blobLength);
  for (var i = 0, offset = 0; offset < blob.length; i++) {
    final take = blob.length - offset < first.shardSize
        ? blob.length - offset
        : first.shardSize;
    blob.setRange(offset, offset + take, shards[i]!);
    offset += take;
  }
  return blob;
}

DataFormatException _error(
  FormatProblem problem, [
  String? detail,
  int? offset,
]) => DataFormatException(
  object: 'fragment',
  problem: problem,
  detail: detail,
  offset: offset,
);

final _magic = Uint8List.fromList('FSFR'.codeUnits);
