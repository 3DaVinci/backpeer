import 'dart:io';

import 'package:agent/agent.dart';
import 'package:cli/cli.dart';
import 'package:node/node.dart';

/// Где слушают фоновые процессы этого пользователя: агент бэкапа — в
/// каталоге программы (`FS_HOME` или стандартный для ОС, как у CLI),
/// хранитель — в папке данных узла (`FS_NODE_DATA_DIR` или стандартная).
final class Endpoints {
  new({required this.home, required this.agent, required this.node});

  factory resolve([Map<String, String>? environment]) {
    final env = environment ?? Platform.environment;
    final home = AppHome.resolve(env: env);
    return Endpoints(
      home: home,
      agent: AgentPaths(home).endpoint(),
      node: ControlEndpoint.forDataDir(
        env['FS_NODE_DATA_DIR'] ?? defaultNodeDataDir(env),
      ),
    );
  }

  final AppHome home;
  final ControlEndpoint agent;
  final ControlEndpoint node;
}
