/// Общий код фоновых процессов ([ADR-008]): хранителя `node` и агента
/// бэкапа `agent`. Без Flutter.
///
/// - локальный API — кадры JSON Lines по Unix-сокету (Windows — loopback
///   с токеном), запросы, ответы и подписка на события
///   (`ControlServer`, `ControlClient`);
/// - журнал JSON Lines с ротацией (`JsonLogWriter`, `RotatingLogFile`);
/// - блокировка папки данных одним процессом (`DirLock`);
/// - службы уровня пользователя ОС и запуск при входе (`UserServices`,
///   `Linger`, `LoginItem`; задачи 5.6.1, 5.6.2, 5.6.4).
///
/// [ADR-008]: ../../ADR/ADR-008%20-%20Два%20фоновых%20процесса%20-%20хранитель%20и%20бэкап.md
library;

export 'src/control_client.dart';
export 'src/control_endpoint.dart';
export 'src/control_server.dart';
export 'src/control_wire.dart';
export 'src/dir_lock.dart';
export 'src/log.dart';
export 'src/login_item.dart';
export 'src/user_services.dart';
