/// Агент бэкапа — фоновый процесс клиента (ADR-008, задачи 5.1.3, 5.1.4).
/// Без Flutter.
///
/// - `BackupAgent` — расписание, бэкап, проверка и восстановление в фоне,
///   продолжение прерванного бэкапа, локальный API (`docs/ops/agent.md`);
/// - `AgentKeyVault`, `SecretStore` — ключи для работы без пароля в
///   хранилище ОС (ADR-010);
/// - `AgentSettings`, `AgentState` — настройки и состояние в каталоге
///   программы (`AgentPaths`);
/// - `KeeperApi`, `NodeLauncher` — включение роли хранителя из приложения
///   (задача 5.5.1);
/// - `assessHealth` — здоровье бэкапа; `PowerSource`, `Notifier`,
///   `SystemEvents` — питание, уведомления, сон и сеть;
/// - `ClientServices`, `ServiceNodeLauncher`, `DaemonBundle`,
///   `PersistentDaemons` — фоновые процессы как службы ОС (задачи 5.6.1,
///   5.6.4, 5.7.3).
library;

export 'src/account_api.dart' show AccountApi;
export 'src/agent_keys.dart';
export 'src/backup_agent.dart';
export 'src/desktop/notifier.dart';
export 'src/desktop/power.dart';
export 'src/desktop/system_events.dart';
export 'src/health.dart';
export 'src/keeper.dart';
export 'src/paths.dart';
export 'src/schedule.dart';
export 'src/secrets/libsecret_store.dart';
export 'src/secrets/secret_store.dart';
export 'src/services.dart';
export 'src/settings.dart';
export 'src/state.dart';
