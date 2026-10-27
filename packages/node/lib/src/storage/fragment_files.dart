import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:node/src/storage/native_fs.dart';
import 'package:protocol/protocol.dart' as pb;

/// Хранилище не выполнило операцию; [code] — ответ собеседнику
/// (`PeerMessage.error`, protocol.md, раздел 3.4), [message] — для
/// журнала.
final class FragmentStorageException implements Exception {
  const new(this.code, this.message);

  final pb.ErrorCode code;
  final String message;

  @override
  String toString() => 'FragmentStorageException(${code.name}: $message)';
}

/// Проверка фрагмента, который приходит частями (data-format.md, раздел 5):
/// заголовок разбирается, как только пришли его 96 байт, корень дерева
/// тела считается по ходу. Ожидаемые идентификатор и размер — из талона
/// (protocol.md, раздел 5), поэтому чужой или лишний фрагмент
/// отклоняется сразу после заголовка, а не после всего тела.
///
/// Ошибки — [FragmentStorageException]: формат и размер — `BAD_REQUEST`,
/// идентификатор и корень дерева — `INTEGRITY_FAILED`.
final class FragmentVerifier {
  new(
    this._crypto, {
    required this.expectedFragmentId,
    required this.expectedSize,
  }) : _merkle = MerkleBuilder(_crypto);

  final CryptoProvider _crypto;
  final Uint8List expectedFragmentId;
  final int expectedSize;
  final MerkleBuilder _merkle;
  final _headerBytes = Uint8List(FragmentHeader.length);
  int _received = 0;
  FragmentHeader? _header;

  /// Сколько байт фрагмента принято.
  int get received => _received;

  /// Заголовок, если его 96 байт уже пришли.
  FragmentHeader? get header => _header;

  /// Хэши листьев дерева тела после [finish] ([MerkleBuilder.leaves]).
  Uint8List get leaves => _merkle.leaves;

  void add(List<int> data) {
    if (_received + data.length > expectedSize) {
      throw FragmentStorageException(
        pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
        'фрагмент длиннее $expectedSize байт',
      );
    }
    var offset = 0;
    if (_received < FragmentHeader.length) {
      offset = min(FragmentHeader.length - _received, data.length);
      _headerBytes.setRange(_received, _received + offset, data);
      _received += offset;
      if (_received == FragmentHeader.length) _checkHeader();
    }
    if (offset < data.length) {
      _merkle.add(
        offset == 0 ? data : Uint8List.fromList(data.sublist(offset)),
      );
      _received += data.length - offset;
    }
  }

  void _checkHeader() {
    final FragmentHeader header;
    try {
      header = FragmentHeader.parse(_headerBytes);
    } on DataFormatException catch (e) {
      throw FragmentStorageException(
        pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
        e.message,
      );
    }
    if (FragmentHeader.length + header.shardSize != expectedSize) {
      throw FragmentStorageException(
        pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
        'размер по заголовку ${FragmentHeader.length + header.shardSize}, '
        'ожидается $expectedSize',
      );
    }
    if (!constantTimeEquals(
      _crypto.blake2b256(_headerBytes),
      expectedFragmentId,
    )) {
      throw const FragmentStorageException(
        pb.ErrorCode.ERROR_CODE_INTEGRITY_FAILED,
        'H(заголовок) не совпадает с fragment_id',
      );
    }
    _header = header;
  }

  /// Завершает проверку: длина и корень дерева тела. Возвращает заголовок.
  FragmentHeader finish() {
    final header = _header;
    if (_received != expectedSize || header == null) {
      throw FragmentStorageException(
        pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
        'фрагмент обрезан: $_received из $expectedSize байт',
      );
    }
    if (!constantTimeEquals(_merkle.finish(), header.bodyRoot)) {
      throw const FragmentStorageException(
        pb.ErrorCode.ERROR_CODE_INTEGRITY_FAILED,
        'корень дерева тела не совпадает с body_root',
      );
    }
    return header;
  }
}

/// Раскладка фрагментов на диске (задача 3.2.1): `<root>/ab/cd/<id>.frag`,
/// где `ab` и `cd` — первые байты `fragment_id` в hex. Два уровня
/// каталогов держат в одном каталоге не больше нескольких тысяч файлов и
/// на десятках терабайт.
///
/// Запись атомарна: фрагмент принимается во временный файл в
/// `<root>/tmp/`, сбрасывается на диск (`fsync`), проверяется и только
/// затем переименовывается в рабочее имя; каталог назначения тоже
/// сбрасывается. Обрыв питания посреди записи оставляет только временный
/// файл, который [prepare] удаляет при следующем запуске.
final class FragmentFiles {
  new(this.root);

  final Directory root;

  static const _suffix = '.frag';

  Directory get _tmp => Directory('${root.path}/tmp');

  /// Создаёт каталоги и удаляет временные файлы прерванных записей;
  /// возвращает их число.
  int prepare() {
    _tmp.createSync(recursive: true);
    var removed = 0;
    for (final entity in _tmp.listSync()) {
      if (entity is File) {
        entity.deleteSync();
        removed++;
      }
    }
    return removed;
  }

  /// Файл фрагмента под рабочим именем.
  File fileOf(List<int> fragmentId) {
    final hex = bytesToHex(fragmentId);
    return File(
      '${root.path}/${hex.substring(0, 2)}/${hex.substring(2, 4)}/'
      '$hex$_suffix',
    );
  }

  /// Новый временный файл для приёма фрагмента.
  Future<FragmentWriter> create() async {
    final name = bytesToHex(
      List<int>.generate(16, (_) => _random.nextInt(256)),
    );
    final file = File('${_tmp.path}/$name.part');
    return FragmentWriter._(this, file, await file.open(mode: FileMode.write));
  }

  /// Переносит принятый и сброшенный на диск временный файл под рабочее
  /// имя [fragmentId] и сбрасывает каталог.
  Future<void> install(File temp, List<int> fragmentId) async {
    final target = fileOf(fragmentId);
    final dir = target.parent;
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
      // Новые каталоги тоже должны пережить обрыв питания.
      fsyncDirectory(dir.parent.path);
      fsyncDirectory(root.path);
    }
    await temp.rename(target.path);
    fsyncDirectory(dir.path);
  }

  /// Удаляет файл фрагмента; отсутствующий — не ошибка.
  void delete(List<int> fragmentId) {
    final file = fileOf(fragmentId);
    try {
      file.deleteSync();
    } on PathNotFoundException {
      return;
    }
    fsyncDirectory(file.parent.path);
  }

  static final _random = Random.secure();
}

/// Временный файл принимаемого фрагмента.
final class FragmentWriter {
  new _(this._files, this.file, this._raf);

  final FragmentFiles _files;
  final File file;
  final RandomAccessFile _raf;
  bool _closed = false;

  Future<void> add(List<int> data) => _raf.writeFrom(data);

  /// Сбрасывает содержимое на диск и закрывает файл.
  Future<void> flush() async {
    await _raf.flush();
    await _raf.close();
    _closed = true;
  }

  /// Под рабочее имя; только после [flush].
  Future<void> install(List<int> fragmentId) {
    if (!_closed) throw StateError('FragmentWriter не сброшен на диск');
    return _files.install(file, fragmentId);
  }

  /// Закрывает и удаляет временный файл.
  Future<void> discard() async {
    if (!_closed) {
      _closed = true;
      await _raf.close();
    }
    try {
      await file.delete();
    } on PathNotFoundException {
      // Уже перенесён или удалён.
    }
  }
}
