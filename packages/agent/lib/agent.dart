/// Агент бэкапа — фоновый процесс клиента (ADR-008, задачи 5.1.3, 5.1.4).
/// Без Flutter.
///
/// - `BackupAgent` — расписание, бэкап, проверка и восстановление в фоне,
///   продолжение прерванного бэкапа, локальный API (`docs/ops/agent.md`);
/// - `AgentKeyVault`, `SecretStore` — ключи для работы без пароля в
///   хранилище ОС (ADR-010);
/// - `AgentSettings`, `AgentState` — настройки и состояние в каталоге
///   программы (`AgentPaths`).
library;

export 'src/agent_keys.dart';
export 'src/backup_agent.dart';
export 'src/paths.dart';
export 'src/schedule.dart';
export 'src/secrets/libsecret_store.dart';
export 'src/secrets/secret_store.dart';
export 'src/settings.dart';
export 'src/state.dart';
