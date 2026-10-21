import 'dart:io';
import 'dart:typed_data';

import 'package:core/src/chunking/chunk_id.dart';
import 'package:core/src/errors.dart';
import 'package:sqlite3/sqlite3.dart';

/// Время и размер файла для кеша файлов: если совпадают с записанными,
/// файл не читается повторно.
///
/// inode не входит: `FileStat` в Dart его не даёт. `ctime` меняется при
/// любой смене метаданных и содержимого, поэтому подмену файла с тем же
/// размером и mtime он тоже замечает.
final class FileStamp {
  const new({
    required this.size,
    required this.modifiedUs,
    required this.changedUs,
  });

  factory fromStat(FileStat stat) => FileStamp(
    size: stat.size,
    modifiedUs: stat.modified.microsecondsSinceEpoch,
    changedUs: stat.changed.microsecondsSinceEpoch,
  );

  final int size;
  final int modifiedUs;
  final int changedUs;
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

  /// Идентификаторы сегментов, ещё не сохранённых (прерванный бэкап).
  List<Uint8List> pendingSegments() => [
    for (final row in _db.select(
      'SELECT segment_id FROM segments WHERE stored = 0 ORDER BY id',
    ))
      row['segment_id'] as Uint8List,
  ];

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
      'AND modified_us = ? AND changed_us = ?',
      [path, stamp.size, stamp.modifiedUs, stamp.changedUs],
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
      'INSERT OR REPLACE INTO files (path, size, modified_us, changed_us, '
      'chunks) VALUES (?, ?, ?, ?, ?)',
      [path, stamp.size, stamp.modifiedUs, stamp.changedUs, packed],
    );
  }

  void removeFile(Uint8List path) =>
      _db.execute('DELETE FROM files WHERE path = ?', [path]);

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
    modified_us INTEGER NOT NULL,
    changed_us INTEGER NOT NULL,
    chunks BLOB NOT NULL
  ) WITHOUT ROWID;
  ''',
];
