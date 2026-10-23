/// Центральный координатор (метаданные, аудиты, репутация узлов). Без Flutter.
///
/// Устройство `lib/src/`:
///
/// - `rpc/` — HTTP-обработчик API, таблица методов, ошибки, сервис на базе;
/// - `accounts/` — учётные записи, устройства, вход по паролю;
/// - `objects/` — снимки и индексы;
/// - `nodes/` — реестр узлов, heartbeat, доступность;
/// - `placement/` — выбор узлов для фрагментов сегмента;
/// - `segments/` — размещение сегментов, талоны, сборка мусора;
/// - `auth/` — проверка подписи `FS-Auth`, защита от повтора, справочник
///   ключей;
/// - `limits/` — ограничение частоты запросов;
/// - `signer/` — процесс-подписант талонов и клиент к нему для веб-сервера;
/// - `db/` — пул PostgreSQL, миграции схемы, таблицы;
/// - `config.dart`, `log.dart`, `server.dart` — настройки, журнал, запуск.
library;

export 'src/accounts/account_service.dart';
export 'src/accounts/certificates.dart';
export 'src/accounts/login_service.dart';
export 'src/admin/admin_access.dart';
export 'src/admin/admin_cli.dart';
export 'src/admin/admin_service.dart';
export 'src/auth/key_directory.dart';
export 'src/auth/replay_cache.dart';
export 'src/auth/request_verifier.dart';
export 'src/config.dart';
export 'src/db/database.dart';
export 'src/db/migrations.dart';
export 'src/db/postgres_key_directory.dart';
export 'src/limits/rate_limiter.dart';
export 'src/log.dart';
export 'src/nodes/node_address.dart';
export 'src/nodes/node_policy.dart';
export 'src/nodes/node_service.dart';
export 'src/nodes/uptime.dart';
export 'src/objects/object_service.dart';
export 'src/placement/placement.dart';
export 'src/placement/placement_policy.dart';
export 'src/rpc/api_handler.dart';
export 'src/rpc/call_context.dart';
export 'src/rpc/database_service.dart';
export 'src/rpc/errors.dart';
export 'src/rpc/methods.dart';
export 'src/rpc/service.dart';
export 'src/segments/segment_service.dart';
export 'src/server.dart';
export 'src/signer/signer_key.dart';
export 'src/signer/signer_server.dart';
export 'src/signer/signer_wire.dart';
export 'src/signer/ticket_signer.dart';
export 'src/signer/ticket_signing_service.dart';
