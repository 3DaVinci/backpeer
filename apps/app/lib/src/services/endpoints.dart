import 'dart:io';

import 'package:agent/agent.dart';
import 'package:cli/cli.dart';
import 'package:node/node.dart';

/// Координатор для новой учётной записи по умолчанию: тестовый стенд на
/// корпоративном Coolify (`docs/ops/coordinator.md`, раздел «Coolify») —
/// до боевого координатора (задача 8.1). Пользователь может указать другой.
const defaultCoordinator = 'https://backpeer-coordinator.app.tridavinci.org';

/// Где слушают фоновые процессы этого пользователя: агент бэкапа — в
/// каталоге программы (`FS_HOME` или стандартный для ОС, как у CLI),
/// хранитель — в папке данных узла (`FS_NODE_DATA_DIR` или стандартная).
final class Endpoints {
  new({
    required this.home,
    required this.agent,
    required this.node,
    this.coordinator = defaultCoordinator,
  });

  factory resolve([Map<String, String>? environment]) {
    final env = environment ?? Platform.environment;
    final home = AppHome.resolve(env: env);
    return Endpoints(
      home: home,
      agent: AgentPaths(home).endpoint(),
      node: ControlEndpoint.forDataDir(
        env['FS_NODE_DATA_DIR'] ?? defaultNodeDataDir(env),
      ),
      coordinator: env['FS_COORDINATOR'] ?? defaultCoordinator,
    );
  }

  final AppHome home;
  final ControlEndpoint agent;
  final ControlEndpoint node;

  /// Координатор, который приложение предлагает для новой учётной записи
  /// (`FS_COORDINATOR` или [defaultCoordinator]).
  final String coordinator;
}
