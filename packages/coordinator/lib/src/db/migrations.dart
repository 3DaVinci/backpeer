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
  Migration(3, 'вход по паролю и отзывы устройств', [
    // Имя для входа добавлено столбцом без NOT NULL: строки, созданные до
    // миграции, остаются; новые учётные записи без имени не создаются.
    r'''
    ALTER TABLE accounts
      ADD COLUMN login text UNIQUE
        CHECK (login ~ '^[a-z0-9][a-z0-9._-]{2,31}$'),
      ADD COLUMN key_bundle bytea,
      ADD COLUMN auth_verifier bytea CHECK (length(auth_verifier) = 32),
      ADD COLUMN key_bundle_updated_at timestamptz,
      ADD CONSTRAINT accounts_key_bundle_pair
        CHECK ((key_bundle IS NULL) = (auth_verifier IS NULL))''',
    'CREATE SEQUENCE device_revocation_seq',
    '''
    ALTER TABLE devices
      ADD COLUMN revocation bytea,
      ADD COLUMN revocation_seq bigint UNIQUE,
      ADD CONSTRAINT devices_revocation_pair
        CHECK ((revocation IS NULL) = (revocation_seq IS NULL))''',
    // Неудачные входы по имени — и для несуществующих имён (protocol.md,
    // раздел 4.7). Ключ — H(имя): имена, которых нет, не хранятся открыто.
    '''
    CREATE TABLE login_attempts (
      login_hash bytea PRIMARY KEY CHECK (length(login_hash) = 32),
      failures integer NOT NULL,
      locked_until timestamptz,
      updated_at timestamptz NOT NULL DEFAULT now()
    )''',
    '''
    CREATE TABLE server_secrets (
      name text PRIMARY KEY,
      value bytea NOT NULL,
      created_at timestamptz NOT NULL DEFAULT now()
    )''',
  ]),
  Migration(4, 'снимки и индексы', [
    // Объекты — в пространстве своей учётной записи: чужой идентификатор
    // не конфликтует и не выдаёт, есть ли такой объект (protocol.md,
    // раздел 4.8).
    '''
    CREATE TABLE objects (
      account_id bytea NOT NULL REFERENCES accounts (account_id),
      kind smallint NOT NULL CHECK (kind IN (1, 2)),
      object_id bytea NOT NULL CHECK (length(object_id) = 32),
      blob bytea NOT NULL,
      size integer NOT NULL CHECK (size > 0),
      sequence bigint NOT NULL CHECK (sequence >= 0),
      stored_at timestamptz NOT NULL,
      PRIMARY KEY (account_id, kind, object_id)
    )''',
    '''
    ALTER TABLE accounts
      ADD COLUMN object_bytes bigint NOT NULL DEFAULT 0
        CHECK (object_bytes >= 0)''',
  ]),
  Migration(5, 'реестр узлов', [
    '''
    ALTER TABLE nodes
      ADD COLUMN capacity_bytes bigint NOT NULL DEFAULT 0
        CHECK (capacity_bytes >= 0),
      ADD COLUMN used_bytes bigint NOT NULL DEFAULT 0
        CHECK (used_bytes >= 0),
      ADD COLUMN endpoints text[] NOT NULL DEFAULT '{}',
      ADD COLUMN versions integer[] NOT NULL DEFAULT '{}',
      ADD COLUMN software text NOT NULL DEFAULT '',
      ADD COLUMN subnet text,
      ADD COLUMN last_heartbeat_at timestamptz,
      ADD COLUMN availability real NOT NULL DEFAULT 0''',
    // Доступность: на каждые сутки UTC — 96 битов по 15 минут, бит
    // взведён, если в интервале был heartbeat (protocol.md, раздел 4.9).
    '''
    CREATE TABLE node_uptime (
      node_id bytea NOT NULL REFERENCES nodes (node_id),
      day integer NOT NULL,
      slots bytea NOT NULL CHECK (length(slots) = 12),
      PRIMARY KEY (node_id, day)
    )''',
    '''
    CREATE INDEX nodes_online ON nodes (last_heartbeat_at)
      WHERE removed_at IS NULL''',
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
