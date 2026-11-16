/// Веб-панель оператора Backpeer (`docs/ops/admin.md`).
///
/// Панель только читает метаданные координатора: учётные записи, балансы,
/// узлы, сегменты, аудиты, ремонт, relay и журнал администратора. Отдельно
/// она принимает обезличенные отчёты о сбоях приложений
/// (`docs/spec/crash-reports.md`) и складывает их в свои файлы.
///
/// Устройство `lib/src/`:
///
/// - `config.dart` — настройки панели, YAML и `FS_ADMIN_*`;
/// - `auth.dart` — пароли операторов, сессии, ограничение попыток входа;
/// - `read_model.dart` — интерфейс чтения и модель данных для API;
/// - `postgres_read_model.dart` — запросы к базе координатора под ролью
///   только для чтения (`fs_admin_web`);
/// - `reports.dart` — приём, очистка, хранение и выборка отчётов о сбоях;
/// - `server.dart` — HTTP: API, вход, статика, заголовки безопасности;
/// - `static_files.dart` — сборка панели из `apps/admin`;
/// - `log.dart` — журнал панели.
library;

export 'src/auth.dart';
export 'src/config.dart';
export 'src/postgres_read_model.dart';
export 'src/read_model.dart';
export 'src/reports.dart';
export 'src/server.dart';
