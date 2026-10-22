import 'dart:typed_data';

import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/crypto/encrypted_blob.dart';
import 'package:core/src/crypto/secret_bytes.dart';
import 'package:core/src/errors.dart';
import 'package:core/src/util/bytes.dart';
import 'package:protobuf/protobuf.dart';
import 'package:protocol/protocol.dart' as pb;

/// Версия формата объектов манифеста (поле `format_version`).
const int manifestFormatVersion = 1;

/// Пределы manifest.md, раздел 8.
const int maxManifestBlobLength = 8 * 1024 * 1024;
const int maxIndexLength = 4 * 1024 * 1024;

/// Снимок и индекс в зашифрованном виде (manifest.md, разделы 2, 4, 5):
/// блоб типа 2 или 3 под `K_manifest`, идентификатор блоба совпадает с
/// `snapshot_id` или `index_id`. Сериализация — каноническая (protobuf
/// для Dart совпадает с protoc, проверено векторами `encoding.json`).
abstract final class ManifestObjects {
  static Uint8List sealSnapshot(
    CryptoProvider crypto,
    SecretBytes manifestKey,
    pb.Snapshot snapshot,
  ) => _seal(
    crypto,
    manifestKey,
    BlobType.snapshot,
    _id(snapshot.snapshotId),
    snapshot,
  );

  static pb.Snapshot openSnapshot(
    CryptoProvider crypto,
    SecretBytes manifestKey,
    Uint8List blob, {
    Uint8List? expectedId,
  }) {
    final (id, plain) = _open(
      crypto,
      manifestKey,
      BlobType.snapshot,
      blob,
      expectedId,
    );
    final snapshot = parseMessage(
      'snapshot',
      () => pb.Snapshot.fromBuffer(plain),
    );
    _checkVersion('snapshot', snapshot.formatVersion);
    _checkId('snapshot', snapshot.snapshotId, id);
    return snapshot;
  }

  static Uint8List sealIndex(
    CryptoProvider crypto,
    SecretBytes manifestKey,
    pb.Index index,
  ) {
    final length = index.writeToBuffer().length;
    if (length > maxIndexLength) {
      throw ArgumentError('Индекс $length байт, предел $maxIndexLength');
    }
    return _seal(
      crypto,
      manifestKey,
      BlobType.indexObject,
      _id(index.indexId),
      index,
    );
  }

  static pb.Index openIndex(
    CryptoProvider crypto,
    SecretBytes manifestKey,
    Uint8List blob, {
    Uint8List? expectedId,
  }) {
    final (id, plain) = _open(
      crypto,
      manifestKey,
      BlobType.indexObject,
      blob,
      expectedId,
    );
    final index = parseMessage('index', () => pb.Index.fromBuffer(plain));
    _checkVersion('index', index.formatVersion);
    _checkId('index', index.indexId, id);
    return index;
  }

  static Uint8List _seal(
    CryptoProvider crypto,
    SecretBytes key,
    BlobType type,
    Uint8List id,
    GeneratedMessage message,
  ) {
    final blob = EncryptedBlob.seal(
      crypto,
      type: type,
      objectId: id,
      key: key,
      plaintext: message.writeToBuffer(),
    );
    if (blob.length > maxManifestBlobLength) {
      throw ArgumentError('Блоб ${blob.length} байт, предел 8 МиБ');
    }
    return blob;
  }

  static (Uint8List, Uint8List) _open(
    CryptoProvider crypto,
    SecretBytes key,
    BlobType type,
    Uint8List blob,
    Uint8List? expectedId,
  ) {
    if (blob.length > maxManifestBlobLength) {
      throw DataFormatException(
        object: type.name,
        problem: FormatProblem.tooLarge,
        detail: '${blob.length} байт',
      );
    }
    final header = BlobHeader.parse(blob);
    final plain = EncryptedBlob.open(
      crypto,
      blob,
      key: key,
      expectedType: type,
      expectedObjectId: expectedId,
    );
    return (header.objectId, plain);
  }

  /// Разбор сообщения Protobuf; любая ошибка разбора —
  /// [DataFormatException]. Пакет `protobuf` 6.1 на отрицательной длине
  /// поля (varint с битом знака) бросает `ArgumentError` или `RangeError`,
  /// а не `InvalidProtocolBufferException` — нашёл фаззинг (1.8.5).
  static T parseMessage<T>(String object, T Function() parse) {
    try {
      return parse();
    } on InvalidProtocolBufferException catch (e) {
      throw DataFormatException(
        object: object,
        problem: FormatProblem.invalidField,
        detail: e.message,
      );
      // Ошибка пакета, а не нашего кода: вход недоверенный.
      // ignore: avoid_catching_errors
    } on ArgumentError catch (e) {
      throw DataFormatException(
        object: object,
        problem: FormatProblem.invalidField,
        detail: '$e',
      );
    }
  }

  static void _checkVersion(String object, int version) {
    if (version != manifestFormatVersion) {
      throw DataFormatException(
        object: object,
        problem: FormatProblem.unsupportedVersion,
        detail: 'format_version $version',
      );
    }
  }

  static void _checkId(String object, List<int> inner, Uint8List blobId) {
    if (!constantTimeEquals(inner, blobId)) {
      throw IntegrityException(
        object: object,
        check: IntegrityCheck.objectId,
        objectId: blobId,
      );
    }
  }

  static Uint8List _id(List<int> id) {
    if (id.length != 32) throw ArgumentError('Идентификатор — 32 байта');
    return Uint8List.fromList(id);
  }
}

/// Собирает записи сегментов в объекты-индексы не больше [maxIndexLength]
/// байт в сериализованном виде; при переполнении начинает следующий
/// (manifest.md, раздел 4).
final class IndexBuilder {
  new(this._newId, {this.limit = maxIndexLength});

  final Uint8List Function() _newId;
  final int limit;
  final List<pb.Index> _done = [];
  pb.Index? _current;
  int _currentLength = 0;

  void add(pb.SegmentRecord record) {
    // Поле 3 (segments): тег, длина varint, тело.
    final body = record.writeToBuffer().length;
    final size = 1 + _varintLength(body) + body;
    final current = _current;
    if (current != null &&
        current.segments.isNotEmpty &&
        _currentLength + size > limit) {
      _done.add(current);
      _current = null;
    }
    if (_current == null) {
      _current = pb.Index(
        formatVersion: manifestFormatVersion,
        indexId: _newId(),
      );
      _currentLength = _current!.writeToBuffer().length;
    }
    if (_currentLength + size > limit) {
      throw ArgumentError('Запись сегмента больше предела индекса');
    }
    _current!.segments.add(record);
    _currentLength += size;
  }

  /// Готовые индексы; текущий закрывается.
  List<pb.Index> finish() {
    if (_current != null) _done.add(_current!);
    _current = null;
    final out = List<pb.Index>.of(_done);
    _done.clear();
    return out;
  }

  static int _varintLength(int value) {
    var n = 1;
    for (var v = value; v >= 0x80; v >>= 7) {
      n++;
    }
    return n;
  }
}

/// Признак возможного отката или сокрытия снимков координатором
/// (manifest.md, раздел 6).
enum RollbackWarning {
  /// Наибольший `sequence` в списке меньше известного устройству.
  sequenceRegressed,

  /// В списке нет последнего снимка этого устройства.
  lastSnapshotMissing,
}

/// Объект в списке с координатора: идентификатор и открытый `sequence`.
typedef ListedObject = ({Uint8List id, int sequence});

/// Сверка списка снимков с локальным состоянием устройства. Ничего не
/// бросает: решать, что делать, — пользователю, поэтому возвращаются
/// предупреждения.
List<RollbackWarning> checkRollback(
  List<ListedObject> listed, {
  required int knownMaxSequence,
  required Uint8List? lastOwnSnapshot,
}) {
  final warnings = <RollbackWarning>[];
  final maxListed = listed.fold(0, (m, o) => o.sequence > m ? o.sequence : m);
  if (maxListed < knownMaxSequence) {
    warnings.add(RollbackWarning.sequenceRegressed);
  }
  if (lastOwnSnapshot != null &&
      !listed.any((o) => constantTimeEquals(o.id, lastOwnSnapshot))) {
    warnings.add(RollbackWarning.lastSnapshotMissing);
  }
  return warnings;
}

/// Номер нового снимка: на 1 больше максимального известного.
int nextSequence(List<ListedObject> listed, int knownMaxSequence) {
  final maxListed = listed.fold(0, (m, o) => o.sequence > m ? o.sequence : m);
  return (maxListed > knownMaxSequence ? maxListed : knownMaxSequence) + 1;
}
