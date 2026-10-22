import 'package:coordinator/src/db/database.dart';
import 'package:postgres/postgres.dart';

/// Шаг схемы базы. Выпущенные миграции не меняются: исправление — новая
/// миграция со следующим номером.
final class Migration {
  const new(this.version, this.name, this.statements);

  final int version;
  final String name;
  final List<String> statements;
}

/// Схема координатора. Таблицы этапа 2 добавляются миграциями задач
/// 2.3–2.7.
const List<Migration> schemaMigrations = [
  Migration(1, 'учётные записи и устройства', [
    '''
    CREATE TABLE accounts (
      account_id bytea PRIMARY KEY CHECK (length(account_id) = 32),
      created_at timestamptz NOT NULL DEFAULT now()
    )''',
    '''
    CREATE TABLE devices (
      device_sign bytea PRIMARY KEY CHECK (length(device_sign) = 32),
      account_id bytea NOT NULL REFERENCES accounts (account_id),
      certificate bytea NOT NULL,
      created_at timestamptz NOT NULL DEFAULT now(),
      revoked_at timestamptz
    )''',
    'CREATE INDEX devices_account_id ON devices (account_id)',
  ]),
  Migration(2, 'узлы', [
    '''
    CREATE TABLE nodes (
      node_id bytea PRIMARY KEY CHECK (length(node_id) = 32),
      account_id bytea NOT NULL REFERENCES accounts (account_id),
      certificate bytea NOT NULL,
      registered_at timestamptz NOT NULL DEFAULT now(),
      removed_at timestamptz
    )''',
    'CREATE INDEX nodes_account_id ON nodes (account_id)',
  ]),
];

/// Схема базы новее, чем знает программа, или список миграций неверен.
final class MigrationException implements Exception {
  const new(this.message);

  final String message;

  @override
  String toString() => 'MigrationException: $message';
}

/// Применяет миграции по порядку, каждую в своей транзакции. Номер версии —
/// в таблице `schema_migrations`. Параллельный запуск из двух процессов
/// безопасен: транзакция берёт advisory-блокировку.
final class Migrator {
  new(this._db, {List<Migration> migrations = schemaMigrations})
    : _migrations = migrations {
    for (var i = 0; i < migrations.length; i++) {
      if (migrations[i].version != i + 1) {
        throw MigrationException(
          'миграции должны идти подряд с 1, на месте ${i + 1} — '
          '${migrations[i].version}',
        );
      }
    }
  }

  final Database _db;
  final List<Migration> _migrations;

  // Произвольная константа блокировки миграций координатора.
  static const _lockId = 0x46530001;

  int get latestVersion => _migrations.length;

  /// Текущая версия схемы; 0 — пустая база.
  Future<int> currentVersion() =>
      _db.transaction((tx) => _version(tx, lock: false));

  /// Применяет миграции до [target] (по умолчанию — до последней).
  /// Возвращает версию схемы после применения.
  Future<int> migrate({int? target}) async {
    final goal = target ?? latestVersion;
    if (goal < 0 || goal > latestVersion) {
      throw MigrationException('нет версии схемы $goal');
    }
    while (true) {
      final applied = await _db.transaction((tx) async {
        final current = await _version(tx, lock: true);
        if (current >= goal) return current;
        final m = _migrations[current];
        for (final statement in m.statements) {
          await tx.execute(statement);
        }
        await tx.execute(
          Sql.named(
            'INSERT INTO schema_migrations (version, name) '
            'VALUES (@v:int4, @n:text)',
          ),
          parameters: {'v': m.version, 'n': m.name},
        );
        return -1;
      });
      if (applied >= 0) return applied;
    }
  }

  Future<int> _version(TxSession tx, {required bool lock}) async {
    if (lock) {
      await tx.execute(
        Sql.named('SELECT pg_advisory_xact_lock(@id:int8)'),
        parameters: {'id': _lockId},
      );
    }
    await tx.execute('''
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version integer PRIMARY KEY,
        name text NOT NULL,
        applied_at timestamptz NOT NULL DEFAULT now()
      )''');
    final rows = await tx.execute(
      'SELECT coalesce(max(version), 0) FROM schema_migrations',
    );
    final version = rows.single.single! as int;
    if (version > latestVersion) {
      throw MigrationException(
        'схема базы версии $version новее программы ($latestVersion)',
      );
    }
    return version;
  }
}
