import 'dart:io';

import 'package:cli/cli.dart';
import 'package:daemon_kit/daemon_kit.dart';

/// Файлы агента в каталоге программы ([AppHome]) — рядом с `config.json`,
/// ключами и локальным индексом, которые он делит с CLI:
///
/// - `agent/settings.json` — что и когда бэкапить (`AgentSettings`);
/// - `agent/state.json` — итоги заданий и незаконченный бэкап
///   (`AgentState`);
/// - `agent/keeper.json` — включена ли роль хранителя и как
///   (`KeeperSettings`, задача 5.5.1);
/// - `agent/keys.agent` — ключи для работы без пароля, под ключом из
///   хранилища ОС (`AgentKeyVault`, ADR-010);
/// - `agent/agent.lock` — один агент на каталог;
/// - `agent/logs/agent.log` — журнал с ротацией;
/// - `agent/run/` — сокет локального API (Windows — порт и токен).
final class AgentPaths {
  new(this.home) : dir = Directory('${home.dir.path}/agent');

  final AppHome home;
  final Directory dir;

  File get settings => File('${dir.path}/settings.json');
  File get state => File('${dir.path}/state.json');
  File get keys => File('${dir.path}/keys.agent');
  File get keeper => File('${dir.path}/keeper.json');
  File get lock => File('${dir.path}/agent.lock');
  String get log => '${dir.path}/logs/agent.log';

  ControlEndpoint endpoint({String? socketPath}) => ControlEndpoint.forDataDir(
    dir.path,
    socketPath: socketPath,
    process: 'агент бэкапа',
  );
}
