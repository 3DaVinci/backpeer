import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:daemon_kit/daemon_kit.dart';
import 'package:logging/logging.dart';
import 'package:node/src/storage/fragment_files.dart';
import 'package:node/src/storage/fragment_index.dart';
import 'package:node/src/storage/native_fs.dart';
import 'package:protocol/protocol.dart' as pb;

/// Повреждённые фрагменты для отчёта координатору (задача 3.2.4).
abstract interface class DamagedFragments {
  /// Ещё не принятые координатором, не больше [limit].
  List<Uint8List> unreportedDamaged({int limit});

  /// Координатор принял отчёт о [fragmentIds].
  void markReported(List<Uint8List> fragmentIds);
}

/// Хранилище фрагментов узла (задачи 3.2.1–3.2.3): файлы
/// ([FragmentFiles]), индекс ([FragmentIndex]), квота и запас свободного
/// места на диске. Обработчики `PutFragment`, `GetFragment`,
/// `DeleteFragment`, `HasFragments` (задача 3.4.1) проверяют талон и
/// собеседника и вызывают эти методы.
///
/// **Порядок записи.** Фрагмент принимается во временный файл и
/// проверяется по ходу ([FragmentVerifier]); после `fsync` в индекс
/// ложится запись [FragmentState.pending], файл переносится под рабочее
/// имя, запись становится [FragmentState.stored]. Удаление — в обратном
/// порядке через [FragmentState.deleting]. При открытии незавершённые
/// записи доводятся до конца или откатываются, временные файлы удаляются:
/// после обрыва питания под рабочим именем нет битых фрагментов, а индекс
/// и файлы совпадают.
///
/// **Место.** Фрагмент не принимается, если вместе с уже хранимыми и
/// принимаемыми он не помещается в квоту или если после него на диске
/// останется меньше [freeReserveBytes] — `QUOTA_EXCEEDED`.
final class FragmentStorage implements DamagedFragments {
  new _({
    required this.files,
    required this.index,
    required this._crypto,
    required this.quotaBytes,
    required this.freeReserveBytes,
    required this._clock,
    required this._diskAvailable,
    required this._onStage,
  });

  /// Открывает хранилище в папке данных [dataDir]: фрагменты в
  /// `fragments/`, индекс — `fragments.db`.
  ///
  /// [diskAvailable] и [onStage] — для тестов: подмена свободного места и
  /// точки останова в записи (`received` — временный файл сброшен,
  /// `journaled` — запись в индексе, `installed` — файл под рабочим
  /// именем).
  factory open(
    String dataDir, {
    required CryptoProvider crypto,
    required int quotaBytes,
    int freeReserveBytes = defaultFreeReserveBytes,
    DateTime Function()? clock,
    int? Function(String path)? diskAvailable,
    Future<void> Function(String stage)? onStage,
  }) {
    final files = FragmentFiles(Directory('$dataDir/fragments'));
    final index = FragmentIndex.open('$dataDir/$indexFile');
    final storage = FragmentStorage._(
      files: files,
      index: index,
      crypto: crypto,
      quotaBytes: quotaBytes,
      freeReserveBytes: freeReserveBytes,
      clock: clock ?? DateTime.now,
      diskAvailable: diskAvailable ?? diskAvailableBytes,
      onStage: onStage,
    );
    try {
      storage._recover();
    } on Object {
      index.close();
      rethrow;
    }
    return storage;
  }

  static const indexFile = 'fragments.db';

  /// Запас свободного места на диске по умолчанию.
  static const defaultFreeReserveBytes = 2000000000;

  static final _log = Logger('storage');

  final FragmentFiles files;
  final FragmentIndex index;
  final CryptoProvider _crypto;

  /// Сколько места узел отдаёт под фрагменты.
  final int quotaBytes;

  /// Сколько места на диске оставлять свободным.
  final int freeReserveBytes;
  final DateTime Function() _clock;
  final int? Function(String path) _diskAvailable;
  final Future<void> Function(String stage)? _onStage;

  final _incoming = <String, IncomingFragment>{};
  int _usedBytes = 0;
  int _count = 0;
  int _damaged = 0;
  bool _closed = false;

  /// Место под фрагментами в индексе (вместе с повреждёнными): то, что
  /// узел сообщает координатору как занятое.
  int get usedBytes => _usedBytes;

  /// Фрагментов в индексе и из них повреждённых.
  int get fragmentCount => _count;
  int get damagedCount => _damaged;

  /// Принимаемых сейчас фрагментов.
  int get incomingCount => _incoming.length;

  /// Свободно на диске с папкой фрагментов; `null` — платформа не
  /// сообщает.
  int? get diskAvailable => _diskAvailable(files.root.path);

  /// Сколько ещё байт фрагментов узел готов принять: меньшее из остатка
  /// квоты и свободного места на диске за вычетом запаса. Место
  /// принимаемых сейчас фрагментов уже вычтено.
  int get freeBytes {
    var reserved = 0;
    var unwritten = 0;
    for (final f in _incoming.values) {
      reserved += f.size;
      unwritten += f.size - f.received;
    }
    var free = quotaBytes - _usedBytes - reserved;
    if (diskAvailable case final disk?) {
      free = min(free, disk - freeReserveBytes - unwritten);
    }
    return max(free, 0);
  }

  void _recover() {
    final temp = files.prepare();
    var completed = 0;
    var rolledBack = 0;
    for (final r in index.inState(FragmentState.pending)) {
      // Файл под рабочим именем появляется только после проверки и fsync:
      // если он есть и размер сходится, запись дошла до конца.
      final file = files.fileOf(r.fragmentId);
      if (file.existsSync() && file.lengthSync() == r.size) {
        index.setState(r.fragmentId, FragmentState.stored);
        completed++;
      } else {
        files.delete(r.fragmentId);
        index.remove(r.fragmentId);
        rolledBack++;
      }
    }
    final deleting = index.inState(FragmentState.deleting);
    for (final r in deleting) {
      files.delete(r.fragmentId);
      index.remove(r.fragmentId);
    }
    _refreshTotals();
    if (temp + completed + rolledBack + deleting.length > 0) {
      _log.warning(
        LogEvent('storage_recovered', {
          'temp_files': temp,
          'completed': completed,
          'rolled_back': rolledBack,
          'deleted': deleting.length,
        }),
      );
    }
  }

  void _refreshTotals() {
    final t = index.totals();
    _usedBytes = t.bytes;
    _count = t.count;
    _damaged = t.damaged;
  }

  /// Запись о фрагменте или `null`.
  FragmentRecord? record(List<int> fragmentId) => index.get(fragmentId);

  /// Начинает приём фрагмента [fragmentId] размера [size] (из талона PUT)
  /// от устройства учётной записи [accountId].
  ///
  /// Отказы — [FragmentStorageException]: фрагмент уже есть —
  /// `ALREADY_EXISTS` (обработчик отвечает успехом, если его загрузила
  /// та же учётная запись); тот же фрагмент уже принимается или
  /// хранилище закрывается — `UNAVAILABLE`; не хватает квоты или места на
  /// диске — `QUOTA_EXCEEDED`.
  Future<IncomingFragment> beginPut({
    required Uint8List fragmentId,
    required int size,
    required Uint8List accountId,
  }) async {
    _checkOpen();
    final key = bytesToHex(fragmentId);
    if (index.get(fragmentId) != null) {
      throw const FragmentStorageException(
        pb.ErrorCode.ERROR_CODE_ALREADY_EXISTS,
        'фрагмент уже хранится',
      );
    }
    if (_incoming.containsKey(key)) {
      throw const FragmentStorageException(
        pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
        'фрагмент уже принимается',
      );
    }
    final free = freeBytes;
    if (size > free) {
      final byQuota = quotaBytes - _usedBytes < size;
      throw FragmentStorageException(
        pb.ErrorCode.ERROR_CODE_QUOTA_EXCEEDED,
        byQuota
            ? 'квота исчерпана: фрагмент $size байт, свободно $free'
            : 'мало места на диске: фрагмент $size байт, свободно $free',
      );
    }
    final incoming = IncomingFragment._(
      this,
      key,
      FragmentVerifier(
        _crypto,
        expectedFragmentId: fragmentId,
        expectedSize: size,
      ),
      Uint8List.fromList(accountId),
    );
    _incoming[key] = incoming;
    try {
      incoming._writer = await files.create();
    } on Object {
      _incoming.remove(key);
      rethrow;
    }
    return incoming;
  }

  Future<FragmentRecord> _commit(IncomingFragment f) async {
    final header = f._verifier.finish();
    final writer = f._writer!;
    await writer.flush();
    await _stage('received');
    final now = _clock();
    final id = f._verifier.expectedFragmentId;
    if (!index.insertPending(
      fragmentId: id,
      accountId: f.accountId,
      size: f.size,
      bodyRoot: header.bodyRoot,
      receivedAt: now,
      leaves: f._verifier.leaves,
    )) {
      throw const FragmentStorageException(
        pb.ErrorCode.ERROR_CODE_ALREADY_EXISTS,
        'фрагмент уже хранится',
      );
    }
    try {
      await _stage('journaled');
      await writer.install(id);
      await _stage('installed');
      index.setState(id, FragmentState.stored);
    } on Object {
      files.delete(id);
      index.remove(id);
      rethrow;
    }
    _usedBytes += f.size;
    _count++;
    return index.get(id)!;
  }

  Future<void> _stage(String stage) async {
    if (_onStage case final hook?) await hook(stage);
  }

  /// Содержимое сохранённого фрагмента потоком. Нет или повреждён —
  /// `NOT_FOUND`.
  Stream<List<int>> openRead(List<int> fragmentId) {
    final r = index.get(fragmentId);
    if (r == null || r.state != FragmentState.stored) {
      throw const FragmentStorageException(
        pb.ErrorCode.ERROR_CODE_NOT_FOUND,
        'фрагмента нет',
      );
    }
    return files.fileOf(fragmentId).openRead();
  }

  /// Доказательство хранения для аудита координатора (задача 4.1.2;
  /// protocol.md, раздел 4.13): блок [blockIndex] тела и путь к нему в
  /// дереве Меркла. Читается только этот блок: хэши листьев лежат в
  /// индексе (у фрагментов, принятых до миграции 3, считаются по файлу
  /// один раз и запоминаются).
  ///
  /// Отказы — [FragmentStorageException]: фрагмента нет или он повреждён —
  /// `NOT_FOUND`; блока с таким номером нет — `BAD_REQUEST`. Блок не
  /// сходится с хэшем листа, файл пропал или обрезан — фрагмент
  /// помечается повреждённым ([onDamaged]) и ответ тот же `NOT_FOUND`.
  Future<AuditProof> prove(List<int> fragmentId, int blockIndex) async {
    _checkOpen();
    final r = index.get(fragmentId);
    if (r == null || r.state != FragmentState.stored) {
      throw const FragmentStorageException(
        pb.ErrorCode.ERROR_CODE_NOT_FOUND,
        'фрагмента нет',
      );
    }
    final bodyLength = r.size - FragmentHeader.length;
    final count = merkleLeafCount(bodyLength);
    if (blockIndex < 0 || blockIndex >= count) {
      throw FragmentStorageException(
        pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
        'блока $blockIndex нет: у фрагмента $count',
      );
    }
    final leaves = await _leavesOf(r, count);
    final length = merkleBlockLength(bodyLength, blockIndex);
    final Uint8List block;
    try {
      final raf = await files.fileOf(fragmentId).open();
      try {
        await raf.setPosition(
          FragmentHeader.length + (blockIndex << merkleBlockLog2),
        );
        block = await raf.read(length);
      } finally {
        await raf.close();
      }
    } on FileSystemException {
      throw _damage(fragmentId, 'файл пропал');
    }
    if (block.length != length ||
        !constantTimeEquals(
          merkleLeafHash(_crypto, block),
          leaves[blockIndex],
        )) {
      throw _damage(fragmentId, 'блок $blockIndex не сходится с деревом');
    }
    return AuditProof(block, merkleAuditPath(_crypto, leaves, blockIndex));
  }

  /// Вызывается, когда аудит нашёл повреждённый фрагмент.
  void Function(Uint8List fragmentId)? onDamaged;

  Future<List<Uint8List>> _leavesOf(FragmentRecord r, int count) async {
    final stored = index.leaves(r.fragmentId);
    if (stored != null && stored.length == 32 * count) {
      final leaves = splitMerkleLeaves(stored);
      if (constantTimeEquals(merkleRootOfLeaves(_crypto, leaves), r.bodyRoot)) {
        return leaves;
      }
    }
    // Хэшей нет (фрагмент принят до миграции 3) или они испорчены:
    // посчитать по файлу и запомнить.
    final builder = MerkleBuilder(_crypto);
    var skip = FragmentHeader.length;
    try {
      await for (final chunk in files.fileOf(r.fragmentId).openRead()) {
        if (skip >= chunk.length) {
          skip -= chunk.length;
          continue;
        }
        builder.add(skip == 0 ? chunk : chunk.sublist(skip));
        skip = 0;
      }
    } on FileSystemException {
      throw _damage(r.fragmentId, 'файл пропал');
    }
    if (builder.length != r.size - FragmentHeader.length ||
        !constantTimeEquals(builder.finish(), r.bodyRoot)) {
      throw _damage(r.fragmentId, 'корень дерева тела не сходится');
    }
    final leaves = builder.leaves;
    index.setLeaves(r.fragmentId, leaves);
    return splitMerkleLeaves(leaves);
  }

  FragmentStorageException _damage(List<int> fragmentId, String reason) {
    markDamaged(fragmentId, 'аудит: $reason');
    _log.warning(
      LogEvent('fragment_damaged', {
        'fragment_id': bytesToHex(fragmentId),
        'reason': reason,
        'source': 'audit',
      }),
    );
    onDamaged?.call(Uint8List.fromList(fragmentId));
    return const FragmentStorageException(
      pb.ErrorCode.ERROR_CODE_NOT_FOUND,
      'фрагмент повреждён',
    );
  }

  /// Какие из [fragmentIds] хранятся и загружены учётной записью
  /// [accountId] (`HasFragments`, protocol.md, раздел 3.4).
  List<bool> has(List<int> accountId, List<List<int>> fragmentIds) => [
    for (final id in fragmentIds)
      switch (index.get(id)) {
        final r? =>
          r.state == FragmentState.stored &&
              constantTimeEquals(r.accountId, accountId),
        null => false,
      },
  ];

  /// Удаляет фрагмент; `false` — его нет. Право на удаление проверяет
  /// вызывающий.
  bool delete(List<int> fragmentId) {
    _checkOpen();
    final r = index.get(fragmentId);
    if (r == null || r.state == FragmentState.pending) return false;
    index.setState(fragmentId, FragmentState.deleting);
    files.delete(fragmentId);
    index.remove(fragmentId);
    _usedBytes -= r.size;
    _count--;
    if (r.state == FragmentState.damaged) _damaged--;
    return true;
  }

  /// Запоминает талон (protocol.md, раздел 5). Уже использован — `false`.
  /// Талоны забываются, когда проверка срока их и так отклонит.
  bool useTicket(List<int> ticketId, DateTime expiresAt) => index.useTicket(
    ticketId,
    expiresAt,
    forgetBefore: _clock().subtract(FragmentTickets.clockSkew),
  );

  /// Талон уже использован ([useTicket]).
  bool isTicketUsed(List<int> ticketId) => index.isTicketUsed(ticketId);

  /// Фрагмент прошёл фоновую проверку.
  void markChecked(List<int> fragmentId) =>
      index.markChecked(fragmentId, _clock());

  /// Фрагмент повреждён или пропал (задача 3.2.4).
  void markDamaged(List<int> fragmentId, String reason) {
    final before = index.get(fragmentId);
    index.markDamaged(fragmentId, reason, _clock());
    if (before?.state == FragmentState.stored) _damaged++;
  }

  @override
  List<Uint8List> unreportedDamaged({int limit = 1000}) =>
      index.unreportedDamaged(limit: limit);

  @override
  void markReported(List<Uint8List> fragmentIds) =>
      index.markReported(fragmentIds, _clock());

  /// Закрывает индекс; принимаемые фрагменты отбрасываются.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final f in _incoming.values.toList()) {
      await f.abort();
    }
    index.close();
  }

  void _checkOpen() {
    if (_closed) {
      throw const FragmentStorageException(
        pb.ErrorCode.ERROR_CODE_UNAVAILABLE,
        'хранилище закрывается',
      );
    }
  }
}

/// Ответ на аудит: блок тела и путь Меркла от листа к корню.
final class AuditProof {
  const new(this.block, this.path);

  final Uint8List block;
  final List<Uint8List> path;
}

/// Принимаемый фрагмент: части по порядку ([add]), затем [commit] или
/// [abort]. Ошибка проверки в [add] или [commit] — фрагмент отброшен.
final class IncomingFragment {
  new _(this._storage, this._key, this._verifier, this.accountId);

  final FragmentStorage _storage;
  final String _key;
  final FragmentVerifier _verifier;
  final Uint8List accountId;
  FragmentWriter? _writer;
  bool _done = false;

  Uint8List get fragmentId => _verifier.expectedFragmentId;
  int get size => _verifier.expectedSize;

  /// Сколько байт принято.
  int get received => _verifier.received;

  /// Очередная часть фрагмента.
  Future<void> add(List<int> data) async {
    if (_done) throw StateError('приём фрагмента завершён');
    try {
      _verifier.add(data);
      await _writer!.add(data);
    } on Object {
      await abort();
      rethrow;
    }
  }

  /// Проверяет фрагмент целиком и сохраняет под рабочим именем.
  Future<FragmentRecord> commit() async {
    if (_done) throw StateError('приём фрагмента завершён');
    _done = true;
    try {
      return await _storage._commit(this);
    } on Object {
      await _writer?.discard();
      rethrow;
    } finally {
      _storage._incoming.remove(_key);
    }
  }

  /// Отбрасывает принятое; повторный вызов ничего не делает.
  Future<void> abort() async {
    if (_done) return;
    _done = true;
    _storage._incoming.remove(_key);
    await _writer?.discard();
  }
}
