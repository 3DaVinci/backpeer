import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/src/chunking/chunk_id.dart';
import 'package:core/src/errors.dart';
import 'package:core/src/snapshot/fs_entry.dart';
import 'package:sqlite3/sqlite3.dart';

/// Вид проверки бэкапа (`cli verify`, задачи 1.6.4, 4.5.2).
enum VerifyMode {
  /// Есть ли фрагменты на узлах (`HasFragments`).
  exists,

  /// Прочитать и проверить все фрагменты и сегменты.
  full,

  /// По данным координатора: живые фрагменты и аудиты, без узлов.
  audits,

  /// Тестовое восстановление случайной выборки сегментов.
  sample,
}

/// Итог проверки бэкапа, который хранит локальный индекс: дата и
/// результат последней проверки каждого вида.
final class VerifyRecord {
  const new({
    required this.mode,
    required this.at,
    required this.segments,
    required this.atRisk,
    required this.unrecoverable,
    required this.problems,
    this.unchecked = 0,
  });

  factory fromJson(Map<String, Object?> json) => VerifyRecord(
    mode: VerifyMode.values.byName(json['mode']! as String),
    at: DateTime.fromMillisecondsSinceEpoch(json['at']! as int, isUtc: true),
    segments: json['segments']! as int,
    atRisk: json['atRisk']! as int,
    unrecoverable: json['unrecoverable']! as int,
    problems: json['problems']! as int,
    // Записи прежних версий этого поля не знают.
    unchecked: json['unchecked'] as int? ?? 0,
  );

  final VerifyMode mode;
  final DateTime at;

  /// Проверено сегментов.
  final int segments;
  final int atRisk;
  final int unrecoverable;

  /// Недостающие или испорченные фрагменты.
  final int problems;

  /// Сегменты, которые не удалось проверить: часть фрагментов на
  /// недоступных узлах. Это не потеря данных.
  final int unchecked;

  bool get isHealthy =>
      atRisk == 0 && unrecoverable == 0 && problems == 0 && unchecked == 0;

  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'at': at.millisecondsSinceEpoch,
    'segments': segments,
    'atRisk': atRisk,
    'unrecoverable': unrecoverable,
    'problems': problems,
    'unchecked': unchecked,
  };
}

/// Размер, время и inode файла для кеша файлов: если совпадают с
/// записанными, файл не читается повторно.
///
/// `ctime` меняется при любой смене содержимого и метаданных, inode — при
/// замене файла другим (например, переименованием поверх).
final class FileStamp {
  const new({
    required this.size,
    required this.mtimeNs,
    required this.ctimeNs,
    this.inode = 0,
  });

  factory fromEntry(FsEntry entry) => FileStamp(
    size: entry.size,
    mtimeNs: entry.mtimeNs,
    ctimeNs: entry.ctimeNs,
    inode: entry.inode,
  );

  /// Из `dart:io`: без inode, время с точностью до микросекунд.
  factory fromStat(FileStat stat) => FileStamp(
    size: stat.size,
    mtimeNs: stat.modified.microsecondsSinceEpoch * 1000,
    ctimeNs: stat.changed.microsecondsSinceEpoch * 1000,
  );

  final int size;
  final int mtimeNs;
  final int ctimeNs;

  /// 0 — неизвестен (Windows).
  final int inode;
}

/// Чанк в оглавлении сегмента.
final class SegmentChunk {
  const new({
    required this.chunkId,
    required this.type,
    required this.offset,
    required this.length,
  });

  final ChunkId chunkId;

  /// 1 — данные файла, 2 — дерево (data-format.md, раздел 3).
  final int type;

  /// Смещение в области данных открытого текста сегмента.
  final int offset;
  final int length;
}

/// Сегмент для записи в индекс.
final class SegmentEntry {
  const new({
    required this.segmentId,
    required this.k,
    required this.n,
    required this.blobLength,
    required this.shardSize,
    required this.fragmentIds,
    required this.chunks,
  });

  final Uint8List segmentId;
  final int k;
  final int n;
  final int blobLength;
  final int shardSize;

  /// n идентификаторов фрагментов по номерам.
  final List<Uint8List> fragmentIds;
  final List<SegmentChunk> chunks;
}

/// Где лежит чанк.
final class ChunkLocation {
  const new({
    required this.segmentId,
    required this.type,
    required this.offset,
    required this.length,
    required this.stored,
  });

  final Uint8List segmentId;
  final int type;
  final int offset;
  final int length;

  /// Сегмент сохранён (записано достаточно фрагментов). `false` — сегмент
  /// из прерванного бэкапа, его ещё нужно дописать.
  final bool stored;
}

/// Фрагмент сегмента в индексе.
final class FragmentEntry {
  const new({required this.number, required this.fragmentId, this.node});

  final int number;
  final Uint8List fragmentId;

  /// Узел, на котором фрагмент сохранён; `null` — ещё не сохранён.
  final String? node;
}

/// Локальный индекс клиента в SQLite (manifest.md, раздел 4): чанк →
/// сегмент и смещение, сегменты и их фрагменты, кеш файлов для
/// инкрементального бэкапа. Индекс восстанавливается из объектов-индексов
/// (задача 1.3.5), поэтому его потеря не теряет данные.
final class LocalIndex {
  new _(this._db);

  /// Открывает или создаёт базу и применяет миграции. База новее, чем
  /// знает программа, — [DataFormatException]; ошибка SQLite —
  /// [StorageException].
  factory open(String path) {
    File(path).parent.createSync(recursive: true);
    return _guard(path, 'open', () => LocalIndex._init(sqlite3.open(path)));
  }

  /// База в памяти — для тестов.
  factory inMemory() => LocalIndex._init(sqlite3.openInMemory());

  factory _init(Database db) {
    final index = LocalIndex._(db);
    try {
      db
        ..execute('PRAGMA journal_mode = WAL')
        // Индекс открывают и CLI, и агент бэкапа: вторая запись ждёт.
        ..execute('PRAGMA busy_timeout = 5000')
        ..execute('PRAGMA synchronous = FULL')
        ..execute('PRAGMA foreign_keys = ON');
      index._migrate();
    } on Object {
      db.close();
      rethrow;
    }
    return index;
  }

  /// Текущая версия схемы.
  static int get latestVersion => _migrations.length;

  final Database _db;

  int get schemaVersion => _db.userVersion;

  void close() => _db.close();

  /// Выполняет [body] в одной транзакции: при исключении всё откатывается.
  /// Вложенные вызовы выполняются в транзакции внешнего.
  T transaction<T>(T Function() body) {
    if (!_db.autocommit) return body();
    _db.execute('BEGIN IMMEDIATE');
    try {
      final result = body();
      _db.execute('COMMIT');
      return result;
    } on Object {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  // --- сегменты и чанки ---------------------------------------------------

  /// Записывает сегмент в состоянии «готовится» вместе с оглавлением и
  /// идентификаторами фрагментов. Чанки, уже известные индексу, не
  /// перезаписываются.
  void addSegment(SegmentEntry segment) {
    if (segment.fragmentIds.length != segment.n) {
      throw ArgumentError('Нужно ${segment.n} идентификаторов фрагментов');
    }
    transaction(() {
      _db.execute(
        'INSERT INTO segments (segment_id, k, n, blob_length, shard_size, '
        'stored) VALUES (?, ?, ?, ?, ?, 0)',
        [
          segment.segmentId,
          segment.k,
          segment.n,
          segment.blobLength,
          segment.shardSize,
        ],
      );
      final rowId = _db.lastInsertRowId;
      final fragment = _db.prepare(
        'INSERT INTO fragments (segment, number, fragment_id) VALUES (?, ?, ?)',
      );
      final chunk = _db.prepare(
        'INSERT OR IGNORE INTO chunks (chunk_id, segment, type, offset, '
        'length) VALUES (?, ?, ?, ?, ?)',
      );
      try {
        for (var i = 0; i < segment.n; i++) {
          fragment.execute([rowId, i, segment.fragmentIds[i]]);
        }
        for (final c in segment.chunks) {
          chunk.execute([c.chunkId.bytes, rowId, c.type, c.offset, c.length]);
        }
      } finally {
        fragment.close();
        chunk.close();
      }
    });
  }

  bool hasSegment(Uint8List segmentId) => _db.select(
    'SELECT 1 FROM segments WHERE segment_id = ?',
    [segmentId],
  ).isNotEmpty;

  /// Отмечает, что фрагмент сохранён на узле [node].
  void setFragmentNode(Uint8List segmentId, int number, String node) {
    _db.execute(
      'UPDATE fragments SET node = ? WHERE number = ? AND segment = '
      '(SELECT id FROM segments WHERE segment_id = ?)',
      [node, number, segmentId],
    );
    _expectUpdated('fragment');
  }

  /// Отмечает сегмент сохранённым.
  void markSegmentStored(Uint8List segmentId) {
    _db.execute('UPDATE segments SET stored = 1 WHERE segment_id = ?', [
      segmentId,
    ]);
    _expectUpdated('segment');
  }

  /// Удаляет сегменты, не дописанные прерванным бэкапом, вместе с их
  /// чанками: эти чанки упакуются заново. Возвращает число удалённых.
  int discardPendingSegments() => transaction(() {
    _db.execute('DELETE FROM segments WHERE stored = 0');
    return _db.updatedRows;
  });

  /// Удаляет сегмент с фрагментами и чанками (сборка мусора). Чанк,
  /// который лежит и в другом сегменте, следующий бэкап при надобности
  /// упакует заново.
  void removeSegment(Uint8List segmentId) =>
      _db.execute('DELETE FROM segments WHERE segment_id = ?', [segmentId]);

  /// Сохранённые сегменты, ещё не попавшие ни в один объект-индекс.
  List<SegmentEntry> segmentsNotInIndex() => [
    for (final row in _db.select(
      'SELECT segment_id FROM segments WHERE stored = 1 AND in_index = 0 '
      'ORDER BY id',
    ))
      segment(row['segment_id'] as Uint8List)!,
  ];

  /// Отмечает, что сегменты записаны в объект-индекс.
  void markInIndex(Iterable<Uint8List> segmentIds) => transaction(() {
    for (final id in segmentIds) {
      _db.execute('UPDATE segments SET in_index = 1 WHERE segment_id = ?', [
        id,
      ]);
    }
  });

  /// Сегмент с оглавлением и идентификаторами фрагментов.
  SegmentEntry? segment(Uint8List segmentId) {
    final rows = _db.select(
      'SELECT id, k, n, blob_length, shard_size FROM segments '
      'WHERE segment_id = ?',
      [segmentId],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    final rowId = row['id'] as int;
    return SegmentEntry(
      segmentId: segmentId,
      k: row['k'] as int,
      n: row['n'] as int,
      blobLength: row['blob_length'] as int,
      shardSize: row['shard_size'] as int,
      fragmentIds: [
        for (final f in _db.select(
          'SELECT fragment_id FROM fragments WHERE segment = ? ORDER BY number',
          [rowId],
        ))
          f['fragment_id'] as Uint8List,
      ],
      chunks: [
        for (final c in _db.select(
          'SELECT chunk_id, type, offset, length FROM chunks WHERE segment = ? '
          'ORDER BY offset',
          [rowId],
        ))
          SegmentChunk(
            chunkId: ChunkId(c['chunk_id'] as Uint8List),
            type: c['type'] as int,
            offset: c['offset'] as int,
            length: c['length'] as int,
          ),
      ],
    );
  }

  /// Идентификаторы сохранённых сегментов, в порядке записи.
  List<Uint8List> storedSegments() => [
    for (final row in _db.select(
      'SELECT segment_id FROM segments WHERE stored = 1 ORDER BY id',
    ))
      row['segment_id'] as Uint8List,
  ];

  /// Идентификаторы сегментов, ещё не сохранённых (прерванный бэкап).
  List<Uint8List> pendingSegments() => [
    for (final row in _db.select(
      'SELECT segment_id FROM segments WHERE stored = 0 ORDER BY id',
    ))
      row['segment_id'] as Uint8List,
  ];

  /// Сколько фрагментов у сохранённых сегментов — для хода проверки.
  int storedFragmentsCount() =>
      _db
              .select(
                'SELECT count(*) AS n FROM fragments f '
                'JOIN segments s ON f.segment = s.id WHERE s.stored = 1',
              )
              .first['n']
          as int;

  List<FragmentEntry> fragments(Uint8List segmentId) => [
    for (final row in _db.select(
      'SELECT number, fragment_id, node FROM fragments WHERE segment = '
      '(SELECT id FROM segments WHERE segment_id = ?) ORDER BY number',
      [segmentId],
    ))
      FragmentEntry(
        number: row['number'] as int,
        fragmentId: row['fragment_id'] as Uint8List,
        node: row['node'] as String?,
      ),
  ];

  ChunkLocation? findChunk(ChunkId id) {
    final rows = _db.select(
      'SELECT s.segment_id, s.stored, c.type, c.offset, c.length '
      'FROM chunks c JOIN segments s ON s.id = c.segment WHERE c.chunk_id = ?',
      [id.bytes],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return ChunkLocation(
      segmentId: row['segment_id'] as Uint8List,
      type: row['type'] as int,
      offset: row['offset'] as int,
      length: row['length'] as int,
      stored: row['stored'] == 1,
    );
  }

  int get chunkCount =>
      _db.select('SELECT count(*) AS n FROM chunks').first['n'] as int;

  // --- кеш файлов ---------------------------------------------------------

  /// Чанки файла из кеша, если размер и время не изменились; иначе `null`.
  /// [path] — путь в байтах ОС (имена на Unix бывают не в UTF-8).
  List<ChunkId>? cachedFile(Uint8List path, FileStamp stamp) {
    final rows = _db.select(
      'SELECT chunks FROM files WHERE path = ? AND size = ? '
      'AND mtime_ns = ? AND ctime_ns = ? AND inode = ?',
      [path, stamp.size, stamp.mtimeNs, stamp.ctimeNs, stamp.inode],
    );
    if (rows.isEmpty) return null;
    final packed = rows.single['chunks'] as Uint8List;
    return [
      for (var i = 0; i < packed.length; i += ChunkId.length)
        ChunkId(Uint8List.sublistView(packed, i, i + ChunkId.length)),
    ];
  }

  void putFile(Uint8List path, FileStamp stamp, List<ChunkId> chunks) {
    final packed = Uint8List(chunks.length * ChunkId.length);
    for (var i = 0; i < chunks.length; i++) {
      packed.setAll(i * ChunkId.length, chunks[i].bytes);
    }
    _db.execute(
      'INSERT OR REPLACE INTO files (path, size, mtime_ns, ctime_ns, inode, '
      'chunks) VALUES (?, ?, ?, ?, ?, ?)',
      [path, stamp.size, stamp.mtimeNs, stamp.ctimeNs, stamp.inode, packed],
    );
  }

  void removeFile(Uint8List path) =>
      _db.execute('DELETE FROM files WHERE path = ?', [path]);

  // --- состояние снимков (защита от отката, manifest.md, раздел 6) -------

  /// Наибольший `sequence`, известный устройству; 0 — снимков не было.
  int get maxSequence =>
      (_db
              .select("SELECT value FROM state WHERE key = 'max_sequence'")
              .firstOrNull?['value']
          as int?) ??
      0;

  /// Последний снимок, сделанный этим устройством.
  Uint8List? get lastOwnSnapshot =>
      _db
              .select("SELECT value FROM state WHERE key = 'last_own_snapshot'")
              .firstOrNull?['value']
          as Uint8List?;

  /// Запоминает снимок этого устройства; `max_sequence` только растёт.
  void recordOwnSnapshot(Uint8List snapshotId, int sequence) {
    transaction(() {
      observeSequence(sequence);
      _db.execute(
        'INSERT OR REPLACE INTO state (key, value) '
        "VALUES ('last_own_snapshot', ?)",
        [snapshotId],
      );
    });
  }

  /// Заменяет последний снимок устройства (после удаления снимка);
  /// `null` — снимков устройства не осталось.
  void setLastOwnSnapshot(Uint8List? snapshotId) {
    if (snapshotId == null) {
      _db.execute("DELETE FROM state WHERE key = 'last_own_snapshot'");
    } else {
      _db.execute(
        'INSERT OR REPLACE INTO state (key, value) '
        "VALUES ('last_own_snapshot', ?)",
        [snapshotId],
      );
    }
  }

  /// Опускает известный максимум после удаления устройством собственного
  /// снимка с наибольшим номером: иначе следующий список выглядел бы как
  /// откат.
  void lowerMaxSequence(int sequence) {
    if (sequence >= maxSequence) return;
    _db.execute(
      "INSERT OR REPLACE INTO state (key, value) VALUES ('max_sequence', ?)",
      [sequence],
    );
  }

  /// Учитывает `sequence`, увиденный в списке снимков.
  void observeSequence(int sequence) {
    if (sequence <= maxSequence) return;
    _db.execute(
      "INSERT OR REPLACE INTO state (key, value) VALUES ('max_sequence', ?)",
      [sequence],
    );
  }

  // --- проверки бэкапа ------------------------------------------------------

  /// Последняя проверка вида [mode] на этом устройстве (задача 4.5.2).
  VerifyRecord? lastVerify(VerifyMode mode) {
    final value = _db.select('SELECT value FROM state WHERE key = ?', [
      'verify.${mode.name}',
    ]).firstOrNull?['value'];
    if (value is! String) return null;
    try {
      return VerifyRecord.fromJson(jsonDecode(value) as Map<String, Object?>);
    } on Object {
      // Запись другой версии программы — как будто проверки не было.
      return null;
    }
  }

  /// Последние проверки всех видов, от новых к старым.
  List<VerifyRecord> verifyHistory() =>
      [for (final mode in VerifyMode.values) ?lastVerify(mode)]
        ..sort((a, b) => b.at.compareTo(a.at));

  /// Запоминает итог проверки вместо прежнего того же вида.
  void recordVerify(VerifyRecord record) => _db.execute(
    'INSERT OR REPLACE INTO state (key, value) VALUES (?, ?)',
    ['verify.${record.mode.name}', jsonEncode(record.toJson())],
  );

  // --- служебное ----------------------------------------------------------

  void _migrate() {
    final current = _db.userVersion;
    if (current > _migrations.length) {
      throw DataFormatException(
        object: 'local-index',
        problem: FormatProblem.unsupportedVersion,
        detail: 'схема $current, программа знает до ${_migrations.length}',
      );
    }
    for (var v = current; v < _migrations.length; v++) {
      transaction(() {
        _db
          ..execute(_migrations[v])
          ..userVersion = v + 1;
      });
    }
  }

  void _expectUpdated(String what) {
    if (_db.updatedRows == 0) {
      throw StorageException(
        location: 'local-index',
        problem: StorageProblem.notFound,
        operation: 'update $what',
      );
    }
  }

  static T _guard<T>(String path, String operation, T Function() body) {
    try {
      return body();
    } on SqliteException catch (e) {
      throw StorageException(
        location: path,
        problem: StorageProblem.io,
        operation: operation,
        cause: e.message,
      );
    }
  }
}

/// Миграции схемы: элемент i переводит базу с версии i на i + 1. Выпущенные
/// миграции не меняются, только добавляются новые.
const _migrations = [
  // 1: сегменты, фрагменты, чанки, кеш файлов.
  '''
  CREATE TABLE segments (
    id INTEGER PRIMARY KEY,
    segment_id BLOB NOT NULL UNIQUE,
    k INTEGER NOT NULL,
    n INTEGER NOT NULL,
    blob_length INTEGER NOT NULL,
    shard_size INTEGER NOT NULL,
    stored INTEGER NOT NULL
  );
  CREATE INDEX segments_pending ON segments (stored) WHERE stored = 0;
  CREATE TABLE fragments (
    segment INTEGER NOT NULL REFERENCES segments (id) ON DELETE CASCADE,
    number INTEGER NOT NULL,
    fragment_id BLOB NOT NULL,
    node TEXT,
    PRIMARY KEY (segment, number)
  ) WITHOUT ROWID;
  CREATE TABLE chunks (
    chunk_id BLOB PRIMARY KEY,
    segment INTEGER NOT NULL REFERENCES segments (id) ON DELETE CASCADE,
    type INTEGER NOT NULL,
    offset INTEGER NOT NULL,
    length INTEGER NOT NULL
  ) WITHOUT ROWID;
  CREATE INDEX chunks_segment ON chunks (segment);
  CREATE TABLE files (
    path BLOB PRIMARY KEY,
    size INTEGER NOT NULL,
    mtime_ns INTEGER NOT NULL,
    ctime_ns INTEGER NOT NULL,
    inode INTEGER NOT NULL,
    chunks BLOB NOT NULL
  ) WITHOUT ROWID;
  ''',
  // 2: состояние снимков устройства для защиты от отката.
  '''
  CREATE TABLE state (
    key TEXT PRIMARY KEY,
    value NOT NULL
  ) WITHOUT ROWID;
  ''',
  // 3: попал ли сохранённый сегмент в объект-индекс. Нужен, чтобы после
  // обрыва бэкапа сегменты, сохранённые до обрыва, вошли в индекс при
  // следующем запуске.
  '''
  ALTER TABLE segments ADD COLUMN in_index INTEGER NOT NULL DEFAULT 0;
  ''',
];
