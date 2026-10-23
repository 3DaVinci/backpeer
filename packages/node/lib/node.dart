/// Демон хранителя (в том числе headless для NAS и Raspberry Pi). Без Flutter.
///
/// - `daemon/` — настройки, журнал, ключи узла, связь с координатором,
///   жизненный цикл демона (задачи 3.1.1, 3.1.2);
/// - `control/` — локальный API управления для CLI и приложения (3.1.3);
/// - `stub_nodes.dart` — узлы-заглушки этапа 2 для разработки и тестов.
library;

export 'src/control/control_client.dart';
export 'src/control/control_endpoint.dart'
    show ControlEndpoint, ControlException;
export 'src/control/control_server.dart';
export 'src/daemon/config.dart';
export 'src/daemon/coordinator_link.dart';
export 'src/daemon/identity.dart';
export 'src/daemon/log.dart';
export 'src/daemon/node_daemon.dart';
export 'src/daemon/transfers.dart';
export 'src/stub_nodes.dart';
