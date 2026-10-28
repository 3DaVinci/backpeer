/// Демон хранителя (в том числе headless для NAS и Raspberry Pi). Без Flutter.
///
/// - `daemon/` — настройки, журнал, ключи узла, связь с координатором,
///   жизненный цикл демона (задачи 3.1.1, 3.1.2);
/// - `storage/` — файлы фрагментов, индекс в SQLite, квота и место,
///   фоновая проверка целостности (3.2), ответ на аудит (4.1.2);
/// - `control/` — локальный API управления для CLI и приложения (3.1.3);
/// - `net/` — приём TCP, проверка достижимости, проброс порта на роутере
///   (UPnP IGD, PCP, NAT-PMP) (3.5), приём UDP после сведения узлов (3.7),
///   приём через relay (3.8);
/// - `peers/` — собеседники по каналу Noise: отозванные устройства (3.3.2),
///   операции с фрагментами, пределы и расписание скорости (3.4);
/// - `stub_nodes.dart` — узлы-заглушки этапа 2 для разработки и тестов.
library;

export 'src/control/control_client.dart';
export 'src/control/control_endpoint.dart'
    show ControlEndpoint, ControlException;
export 'src/control/control_server.dart';
export 'src/daemon/command_channel.dart';
export 'src/daemon/config.dart';
export 'src/daemon/coordinator_link.dart';
export 'src/daemon/identity.dart';
export 'src/daemon/log.dart';
export 'src/daemon/node_daemon.dart';
export 'src/daemon/transfers.dart';
export 'src/net/peer_listener.dart';
export 'src/net/port_mapping/local_network.dart';
export 'src/net/port_mapping/pcp.dart';
export 'src/net/port_mapping/port_mapper.dart';
export 'src/net/port_mapping/port_mapping.dart';
export 'src/net/port_mapping/upnp.dart';
export 'src/net/reachability.dart';
export 'src/net/relay_peers.dart';
export 'src/net/udp_peers.dart';
export 'src/peers/peer_service.dart';
export 'src/peers/revocations.dart';
export 'src/peers/speed_schedule.dart';
export 'src/repair/repair_executor.dart';
export 'src/storage/audits.dart';
export 'src/storage/fragment_files.dart';
export 'src/storage/fragment_index.dart';
export 'src/storage/fragment_storage.dart';
export 'src/storage/integrity_checker.dart';
export 'src/storage/native_fs.dart';
export 'src/stub_nodes.dart';
