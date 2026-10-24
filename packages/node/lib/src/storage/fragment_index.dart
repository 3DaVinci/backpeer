import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:sqlite3/sqlite3.dart';

/// Состояние фрагмента в индексе.
enum FragmentState {
  /// Запись начата: проверенный фрагмент переносится под рабочее имя.
  /// После сбоя [FragmentIndex] доводит её до конца или откатывает.
  pending,

  /// Хранится и выдаётся.
  stored,

  /// Удаляется: файл может ещё лежать на диске.
  deleting,

  /// Не прошёл фоновую проверку или пропал с диска (задача 3.2.4): не
  /// выдаётся, место занимает до ремонта или удаления (этап 4).
  damaged,
}

/// Фрагмент в индексе.
final class FragmentRecord {
  const new({
    required this.fragmentId,
    required this.accountId,
    required this.size,
    required this.bodyRoot,
    required this.receivedAt,
    required this.state,
    required this.checkedAt,
    this.damage,
    this.reportedAt,
  });

  final Uint8List fragmentId;

  /// Учётная запись загрузившего устройства: удалять фрагмент и спрашивать
  /// о нём `HasFragments` может только она (protocol.md, раздел 5).
  final Uint8List accountId;

  /// Размер фрагмента с заголовком.
  final int size;
  final Uint8List bodyRoot;
  final DateTime receivedAt;
  final FragmentState state;

  /// Последняя успешная проверка целостности (при приёме — время приёма).
  final DateTime checkedAt;

  /// Почему фрагмент повреждён.
  final String? damage;

  /// Когда координатор принял отчёт о повреждении.
  final DateTime? reportedAt;
}

/// Индекс хранителя в SQLite (задача 3.2.2): фрагменты (кто загрузил,
/// размер, `body_root`, время приёма, состояние), использованные талоны
/// до их истечения (protocol.md, раздел 5) и отозванные устройства
/// (раздел 4.7). Файлы фрагментов —
/// `FragmentFiles`; индекс — источник правды о том, что узел хранит.
///
/// Запись идёт с `synchronous = FULL`: принятый фрагмент и использованный
/// талон переживают обрыв питания.
final class FragmentIndex {
  new _(this._db);

  /// Открывает или создаёт базу (права 0600) и применяет миграции. База
  /// новее программы — [StateError].
  factory open(String path) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    if (!file.existsSync()) {
      file.createSync();
      if (!Platform.isWindows) restrictToOwner(path);
    }
    return FragmentIndex._init(sqlite3.open(path));
  }

  /// База в памяти — для тестов.
  factory inMemory() => FragmentIndex._init(sqlite3.openInMemory());

  factory _init(Database db) {
    try {
      db
        ..execute('PRAGMA journal_mode = WAL')
        ..execute('PRAGMA synchronous = FULL');
      final version = db.userVersion;
      if (version > _migrations.length) {
        throw StateError(
          'индекс узла версии $version новее программы '
          '(${_migrations.length})',
        );
      }
      for (var v = version; v < _migrations.length; v++) {
        db
          ..execute('BEGIN IMMEDIATE')
          ..execute(_migrations[v])
          ..userVersion = v + 1
          ..execute('COMMIT');
      }
    } on Object {
      db.close();
      rethrow;
    }
    return FragmentIndex._(db);
  }

  final Database _db;

  void close() => _db.close();

  // --- фрагменты -----------------------------------------------------------

  FragmentRecord? get(List<int> fragmentId) {
    final rows = _db.select('$_select WHERE fragment_id = ?', [fragmentId]);
    return rows.isEmpty ? null : _record(rows.single);
  }

  /// Начало записи: фрагмент в состоянии [FragmentState.pending]. Уже
  /// есть запись — `false`.
  bool insertPending({
    required List<int> fragmentId,
    required List<int> accountId,
    required int size,
    required List<int> bodyRoot,
    required DateTime receivedAt,
  }) {
    _db.execute(
      'INSERT OR IGNORE INTO fragments (fragment_id, account_id, size, '
      'body_root, received_at, state, checked_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        fragmentId,
        accountId,
        size,
        bodyRoot,
        receivedAt.millisecondsSinceEpoch,
        FragmentState.pending.index,
        receivedAt.millisecondsSinceEpoch,
      ],
    );
    return _db.updatedRows == 1;
  }

  void setState(List<int> fragmentId, FragmentState state) => _db.execute(
    'UPDATE fragments SET state = ? WHERE fragment_id = ?',
    [state.index, fragmentId],
  );

  void remove(List<int> fragmentId) =>
      _db.execute('DELETE FROM fragments WHERE fragment_id = ?', [fragmentId]);

  /// Фрагменты в состоянии [state] — для восстановления после сбоя.
  List<FragmentRecord> inState(FragmentState state) => [
    for (final row in _db.select('$_select WHERE state = ?', [state.index]))
      _record(row),
  ];

  /// Фрагменты, которые хранит узел: размер и количество по состояниям,
  /// кроме [FragmentState.deleting].
  ({int bytes, int count, int damaged}) totals() {
    final row = _db.select(
      'SELECT coalesce(sum(size), 0) AS bytes, count(*) AS count, '
      'coalesce(sum(state = ?), 0) AS damaged '
      'FROM fragments WHERE state <> ?',
      [FragmentState.damaged.index, FragmentState.deleting.index],
    ).single;
    return (
      bytes: row['bytes'] as int,
      count: row['count'] as int,
      damaged: row['damaged'] as int,
    );
  }

  /// Сохранённый фрагмент, дольше всех не проверявшийся, если последняя
  /// проверка была не позже [checkedBefore].
  FragmentRecord? nextToCheck(DateTime checkedBefore) {
    final rows = _db.select(
      '$_select WHERE state = ? AND checked_at <= ? '
      'ORDER BY checked_at LIMIT 1',
      [FragmentState.stored.index, checkedBefore.millisecondsSinceEpoch],
    );
    return rows.isEmpty ? null : _record(rows.single);
  }

  /// Фрагмент прошёл проверку в [at].
  void markChecked(List<int> fragmentId, DateTime at) => _db.execute(
    'UPDATE fragments SET checked_at = ? WHERE fragment_id = ? AND state = ?',
    [at.millisecondsSinceEpoch, fragmentId, FragmentState.stored.index],
  );

  /// Фрагмент повреждён или пропал: [reason] — для журнала и отчёта.
  void markDamaged(List<int> fragmentId, String reason, DateTime at) =>
      _db.execute(
        'UPDATE fragments SET state = ?, damage = ?, checked_at = ?, '
        'reported_at = NULL WHERE fragment_id = ? AND state = ?',
        [
          FragmentState.damaged.index,
          reason,
          at.millisecondsSinceEpoch,
          fragmentId,
          FragmentState.stored.index,
        ],
      );

  /// Повреждённые фрагменты, о которых координатор ещё не знает.
  List<Uint8List> unreportedDamaged({int limit = 1000}) => [
    for (final row in _db.select(
      'SELECT fragment_id FROM fragments WHERE state = ? AND '
      'reported_at IS NULL ORDER BY checked_at LIMIT ?',
      [FragmentState.damaged.index, limit],
    ))
      row['fragment_id'] as Uint8List,
  ];

  void markReported(List<List<int>> fragmentIds, DateTime at) =>
      _transaction(() {
        final update = _db.prepare(
          'UPDATE fragments SET reported_at = ? WHERE fragment_id = ? '
          'AND state = ?',
        );
        try {
          for (final id in fragmentIds) {
            update.execute([
              at.millisecondsSinceEpoch,
              id,
              FragmentState.damaged.index,
            ]);
          }
        } finally {
          update.close();
        }
      });

  // --- талоны --------------------------------------------------------------

  /// Запоминает талон [ticketId] со сроком [expiresAt]. Талон уже
  /// использован — `false` (protocol.md, раздел 5). Заодно забывает
  /// талоны, истёкшие до [forgetBefore]: их и так отклонит проверка срока.
  bool useTicket(
    List<int> ticketId,
    DateTime expiresAt, {
    required DateTime forgetBefore,
  }) => _transaction(() {
    _db
      ..execute('DELETE FROM used_tickets WHERE expires_at < ?', [
        forgetBefore.millisecondsSinceEpoch,
      ])
      ..execute(
        'INSERT OR IGNORE INTO used_tickets (ticket_id, expires_at) '
        'VALUES (?, ?)',
        [ticketId, expiresAt.millisecondsSinceEpoch],
      );
    return _db.updatedRows == 1;
  });

  /// Использован ли талон [ticketId] (и ещё не забыт).
  bool isTicketUsed(List<int> ticketId) => _db.select(
    'SELECT 1 FROM used_tickets WHERE ticket_id = ?',
    [ticketId],
  ).isNotEmpty;

  /// Сколько талонов помнит узел.
  int get usedTicketCount =>
      _db.select('SELECT count(*) AS c FROM used_tickets').single['c'] as int;

  // --- отзывы устройств ---------------------------------------------------

  /// Номер последнего отзыва, полученного от координатора
  /// (`ListRevocations.after_sequence`), 0 — ещё ни одного.
  int get revocationSequence {
    final rows = _db.select(
      "SELECT value FROM sync_state WHERE name = 'revocation_sequence'",
    );
    return rows.isEmpty ? 0 : rows.single['value'] as int;
  }

  /// Запоминает отзывы [revocations] и номер [sequence], до которого
  /// дочитан список, в одной транзакции. Повтор отзыва — без изменений.
  void addRevocations(List<RevokedDevice> revocations, int sequence) =>
      _transaction(() {
        final insert = _db.prepare(
          'INSERT OR IGNORE INTO revoked_devices '
          '(device_sign, account_id, revoked_at, sequence) VALUES (?, ?, ?, ?)',
        );
        try {
          for (final r in revocations) {
            insert.execute([
              r.deviceSign,
              r.accountId,
              r.revokedAt.millisecondsSinceEpoch,
              r.sequence,
            ]);
          }
        } finally {
          insert.close();
        }
        _db.execute(
          'INSERT INTO sync_state (name, value) '
          "VALUES ('revocation_sequence', ?) "
          'ON CONFLICT (name) DO UPDATE SET value = max(value, excluded.value)',
          [sequence],
        );
      });

  /// Все отозванные устройства.
  List<Uint8List> revokedDeviceKeys() => [
    for (final row in _db.select('SELECT device_sign FROM revoked_devices'))
      row['device_sign'] as Uint8List,
  ];

  T _transaction<T>(T Function() body) {
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

  static const _select =
      'SELECT fragment_id, account_id, size, body_root, received_at, state, '
      'checked_at, damage, reported_at FROM fragments';

  static FragmentRecord _record(Row row) => FragmentRecord(
    fragmentId: row['fragment_id'] as Uint8List,
    accountId: row['account_id'] as Uint8List,
    size: row['size'] as int,
    bodyRoot: row['body_root'] as Uint8List,
    receivedAt: _time(row['received_at'] as int),
    state: FragmentState.values[row['state'] as int],
    checkedAt: _time(row['checked_at'] as int),
    damage: row['damage'] as String?,
    reportedAt: switch (row['reported_at']) {
      final int ms => _time(ms),
      _ => null,
    },
  );

  static DateTime _time(int ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
}

/// Отзыв устройства, полученный от координатора (protocol.md,
/// раздел 4.7) и проверенный узлом.
final class RevokedDevice {
  const new({
    required this.deviceSign,
    required this.accountId,
    required this.revokedAt,
    required this.sequence,
  });

  final Uint8List deviceSign;
  final Uint8List accountId;
  final DateTime revokedAt;

  /// Номер записи в `ListRevocations`.
  final int sequence;
}

/// Миграции: элемент i переводит базу с версии i на i + 1. Выпущенные
/// миграции не меняются.
const _migrations = [
  // 1: фрагменты и использованные талоны.
  '''
  CREATE TABLE fragments (
    fragment_id BLOB PRIMARY KEY CHECK (length(fragment_id) = 32),
    account_id BLOB NOT NULL CHECK (length(account_id) = 32),
    size INTEGER NOT NULL CHECK (size > 0),
    body_root BLOB NOT NULL CHECK (length(body_root) = 32),
    received_at INTEGER NOT NULL,
    state INTEGER NOT NULL CHECK (state BETWEEN 0 AND 3),
    checked_at INTEGER NOT NULL,
    damage TEXT,
    reported_at INTEGER
  ) WITHOUT ROWID;
  CREATE INDEX fragments_account ON fragments (account_id);
  CREATE INDEX fragments_check ON fragments (state, checked_at);
  CREATE TABLE used_tickets (
    ticket_id BLOB PRIMARY KEY CHECK (length(ticket_id) = 16),
    expires_at INTEGER NOT NULL
  ) WITHOUT ROWID;
  CREATE INDEX used_tickets_expires ON used_tickets (expires_at);
  ''',
  // 2: отозванные устройства и место, до которого прочитан их список
  // (задача 3.3.2).
  '''
  CREATE TABLE revoked_devices (
    device_sign BLOB PRIMARY KEY CHECK (length(device_sign) = 32),
    account_id BLOB NOT NULL CHECK (length(account_id) = 32),
    revoked_at INTEGER NOT NULL,
    sequence INTEGER NOT NULL
  ) WITHOUT ROWID;
  CREATE TABLE sync_state (
    name TEXT PRIMARY KEY,
    value INTEGER NOT NULL
  ) WITHOUT ROWID;
  ''',
];
