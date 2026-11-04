import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:cli/src/context.dart';
import 'package:core/core.dart';
import 'package:node/node.dart';
import 'package:protocol/protocol.dart' as pb;

/// Управление демоном узла-хранителя на этом компьютере через его
/// локальный API (задача 3.1.3; `docs/ops/node.md`, раздел «Локальный
/// API»). Подключиться может только пользователь ОС, от которого запущен
/// демон.
final class NodeCommand extends CliCommand {
  new(super.ctx) {
    addSubcommand(_NodeStatusCommand(ctx));
    addSubcommand(_NodeStatsCommand(ctx));
    addSubcommand(_NodeLimitsCommand(ctx));
    addSubcommand(_NodeStateCommand(ctx, 'pause'));
    addSubcommand(_NodeStateCommand(ctx, 'resume'));
    addSubcommand(_NodeStateCommand(ctx, 'stop'));
    addSubcommand(_NodeExitCommand(ctx));
    addSubcommand(_NodePairCommand(ctx));
  }

  @override
  String get name => 'node';

  @override
  String get description =>
      'Демон узла-хранителя на этом компьютере: состояние, пределы, пауза.';
}

abstract class _NodeSubcommand extends CliCommand {
  new(super.ctx) {
    argParser
      ..addOption(
        'node-data',
        help:
            'Папка данных узла (по умолчанию FS_NODE_DATA_DIR или '
            'стандартная для ОС)',
      )
      ..addOption(
        'socket',
        help: 'Сокет локального API, если задан control.socket',
      );
  }

  /// Вызов [method] демона; демон не запущен или отказал — [CliException].
  Future<Map<String, Object?>> callNode(
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    final a = argResults!;
    final data =
        a.option('node-data') ??
        ctx.env[NodeConfig.envName('data.dir')] ??
        defaultNodeDataDir(ctx.env);
    final endpoint = ControlEndpoint.forDataDir(
      data,
      socketPath:
          a.option('socket') ?? ctx.env[NodeConfig.envName('control.socket')],
    );
    try {
      final client = await NodeControlClient.connect(endpoint);
      try {
        return await client.call(method, params);
      } finally {
        await client.close();
      }
    } on ControlException catch (e) {
      throw CliException(
        e.code == 'unavailable'
            ? '${e.message} (папка данных $data)'
            : 'демон узла: ${e.message}',
      );
    }
  }
}

final class _NodeStatusCommand extends _NodeSubcommand {
  new(super.ctx);

  @override
  String get name => 'status';

  @override
  String get description => 'Состояние демона узла.';

  @override
  Future<int> run() async {
    final s = await callNode('status');
    final limits = s['limits'] as Map<String, Object?>?;
    final coordinator = s['coordinator'] as Map<String, Object?>?;
    final nodeId = '${s['nodeId']}';
    ctx.report
      ..info(
        'Узел ${nodeId.substring(0, 16)}… — '
        '${_state[s['state']] ?? s['state']}',
      )
      ..info('Версия ${s['version']}, запущен ${s['startedAt']}')
      ..info('Папка данных: ${s['dataDir']}')
      ..info(
        'Место: ${_size(s['usedBytes'])} из ${_size(s['quotaBytes'])}, '
        'передач сейчас: ${s['activeTransfers']}',
      )
      ..info(
        'Фрагментов: ${s['fragments']}, повреждённых: '
        '${s['damagedFragments']}; примет ещё ${_size(s['freeBytes'])}',
      )
      ..info(_limits(limits))
      ..info('Соединений с собеседниками: ${s['connections'] ?? 0}')
      ..info(
        _network(
          s['listen'] as Map<String, Object?>?,
          s['portMapping'] as Map<String, Object?>?,
          s['reachability'] as Map<String, Object?>?,
        ),
      )
      ..info(_coordinator(coordinator));
    if (_exit(coordinator?['exit'] as Map<String, Object?>?)
        case final String line) {
      ctx.report.info(line);
    }
    if (_reconcile(coordinator?['reconcile'] as Map<String, Object?>?)
        case final String line) {
      ctx.report.info(line);
    }
    ctx.report.result(s);
    if (s['damagedFragments'] case final int damaged when damaged > 0) {
      ctx.report.warn(
        'Повреждённых фрагментов: $damaged — проверьте диск; координатор '
        'получает отчёт о них',
      );
    }
    if (coordinator?['unknownCoordinatorKeys'] case final List<Object?> keys
        when keys.isNotEmpty) {
      ctx.report.warn(
        'Координатор подписывает ключами, которых нет у узла '
        '(${keys.join(', ')}): нужно обновление',
      );
    }
    return ExitCode.ok;
  }

  /// Основные пределы и, если расписание их сейчас меняет, действующие.
  static String _limits(Map<String, Object?>? l) {
    final line =
        'Пределы: отдача ${_rate(l?['uploadBytesPerSecond'])}, '
        'приём ${_rate(l?['downloadBytesPerSecond'])}';
    final e = l?['effective'] as Map<String, Object?>?;
    if (e == null ||
        (e['uploadBytesPerSecond'] == l?['uploadBytesPerSecond'] &&
            e['downloadBytesPerSecond'] == l?['downloadBytesPerSecond'])) {
      return line;
    }
    return '$line; по расписанию сейчас отдача '
        '${_rate(e['uploadBytesPerSecond'])}, приём '
        '${_rate(e['downloadBytesPerSecond'])}';
  }

  /// Приём соединений, проброс порта и доступность извне (3.5).
  static String _network(
    Map<String, Object?>? listen,
    Map<String, Object?>? mapping,
    Map<String, Object?>? reachability,
  ) {
    if (listen == null) return 'Приём соединений: нет (нет сертификата узла)';
    final parts = ['Приём соединений: порт ${listen['port']}'];
    final m = mapping?['mapping'] as Map<String, Object?>?;
    if (m != null) {
      parts.add('проброс ${m['method']} → внешний порт ${m['externalPort']}');
    } else if (mapping?['enabled'] == true) {
      parts.add('проброса нет');
    }
    if (reachability != null && reachability['checkedAt'] != null) {
      final endpoints = (reachability['endpoints'] as List<Object?>?) ?? [];
      parts.add(
        reachability['reachable'] == true
            ? 'доступен извне (${endpoints.join(', ')})'
            : 'извне недоступен',
      );
    }
    return parts.join('; ');
  }

  static String _coordinator(Map<String, Object?>? c) {
    if (c == null) return 'Координатор: не задан';
    final registered = c['registered'] == true
        ? 'зарегистрирован'
        : 'не зарегистрирован';
    final beat = c['lastHeartbeatAt'];
    final error = c['lastError'];
    final channel = switch (c['channel']) {
      {'connected': true} => ', канал команд открыт',
      Map<String, Object?>() => ', канал команд не открыт',
      _ => '',
    };
    return 'Координатор ${c['url']}: $registered'
        '${beat == null ? '' : ', связь $beat'}$channel'
        '${error == null ? '' : '; ошибка: $error'}';
  }

  /// Выход из сети (4.4.1): сколько ещё перенести.
  static String? _exit(Map<String, Object?>? e) {
    if (e == null) return null;
    final left = e['remainingFragments'];
    return left == null
        ? 'Выход из сети: объявлен, ход переноса ещё не известен'
        : 'Выход из сети: осталось перенести фрагментов: $left '
              '(${_size(e['remainingBytes'])})';
  }

  /// Сверка фрагментов с координатором (4.4.3).
  static String? _reconcile(Map<String, Object?>? r) {
    if (r == null) return null;
    final last = r['lastPassAt'] ?? 'не было';
    final orphans = r['orphans'];
    return 'Сверка с координатором: последняя $last; '
        'не учтённых координатором фрагментов: $orphans'
        '${orphans == 0 ? '' : ' (${_size(r['orphanBytes'])}, удаляются '
                  'после карантина)'}';
  }

  static const _state = {
    'running': 'работает',
    'paused': 'на паузе',
    'stopping': 'останавливается',
  };
}

final class _NodeStatsCommand extends _NodeSubcommand {
  new(super.ctx);

  @override
  String get name => 'stats';

  @override
  String get description => 'Статистика демона узла с запуска.';

  @override
  Future<int> run() async {
    final s = await callNode('stats');
    ctx.report
      ..info('С запуска (${s['uptimeSeconds']} с):')
      ..info(
        '  принято ${_size(s['bytesReceived'])} '
        '(фрагментов: ${s['fragmentsReceived']}), '
        'отдано ${_size(s['bytesSent'])} '
        '(фрагментов: ${s['fragmentsSent']})',
      )
      ..info(
        '  удалено фрагментов: ${s['fragmentsDeleted']}, '
        'отклонено запросов: ${s['requestsRejected']}, '
        'передач сейчас: ${s['activeTransfers']}',
      )
      ..info(
        '  проверено фрагментов: ${s['fragmentsChecked']}, '
        'найдено повреждённых: ${s['fragmentsDamaged']}',
      )
      ..result(s);
    return ExitCode.ok;
  }
}

final class _NodeLimitsCommand extends _NodeSubcommand {
  new(super.ctx) {
    argParser
      ..addOption(
        'upload',
        help: 'Предел отдачи, байт в секунду (0 — без предела)',
      )
      ..addOption(
        'download',
        help: 'Предел приёма, байт в секунду (0 — без предела)',
      );
  }

  @override
  String get name => 'limits';

  @override
  String get description =>
      'Показать или изменить пределы скорости (до перезапуска демона; '
      'постоянные — в настройках узла).';

  @override
  Future<int> run() async {
    final a = argResults!;
    final params = <String, Object?>{
      for (final key in ['upload', 'download'])
        if (a.option(key) case final String v) key: _parse(key, v),
    };
    final s = await callNode('limits', params);
    ctx.report.info(_NodeStatusCommand._limits(s));
    if (s['schedule'] case final List<Object?> rules when rules.isNotEmpty) {
      ctx.report.info('Расписание: ${rules.join('; ')}');
    }
    ctx.report.result(s);
    return ExitCode.ok;
  }

  static int _parse(String key, String value) {
    final n = int.tryParse(value);
    if (n == null || n < 0) {
      throw UsageException('--$key: целое число байт в секунду', '');
    }
    return n;
  }
}

/// `pause`, `resume`, `stop`.
final class _NodeStateCommand extends _NodeSubcommand {
  new(super.ctx, this.name);

  @override
  final String name;

  @override
  String get description => switch (name) {
    'pause' => 'Пауза: не принимать новые передачи (начатые завершаются).',
    'resume' => 'Снять паузу.',
    _ => 'Остановить демон (начатые передачи завершаются).',
  };

  @override
  Future<int> run() async {
    final s = await callNode(name);
    ctx.report
      ..info(switch (name) {
        'pause' => 'Узел на паузе.',
        'resume' => 'Узел работает.',
        _ => 'Узел останавливается.',
      })
      ..result(s);
    return ExitCode.ok;
  }
}

/// `exit`: выход узла из сети (задача 4.4.1).
final class _NodeExitCommand extends _NodeSubcommand {
  new(super.ctx) {
    argParser.addFlag(
      'cancel',
      negatable: false,
      help: 'Отменить выход: перенесённые фрагменты остаются на новых узлах',
    );
  }

  @override
  String get name => 'exit';

  @override
  String get description =>
      'Выйти из сети: координатор перестаёт размещать на узле фрагменты и '
      'переносит его фрагменты на другие узлы; когда переносить нечего, '
      'узел удаляет их и останавливается. Повторный вызов показывает ход.';

  @override
  Future<int> run() async {
    final cancel = argResults!.flag('cancel');
    final s = await callNode('exit', {'cancel': cancel});
    ctx.report
      ..info(switch (s) {
        _ when cancel => 'Выход отменён.',
        {'done': true} =>
          'Перенос закончен: узел удалён из сети, удаляет фрагменты и '
              'останавливается.',
        _ =>
          'Выход объявлен: осталось перенести фрагментов: '
              '${s['remainingFragments']} (${_size(s['remainingBytes'])}). '
              'Не выключайте узел до конца переноса; ход — cli node status.',
      })
      ..result(s);
    return ExitCode.ok;
  }
}

String _size(Object? bytes) => bytes is int ? formatSize(bytes) : '?';

String _rate(Object? bytesPerSecond) =>
    bytesPerSecond == 0 ? 'без предела' : '${_size(bytesPerSecond)}/с';

/// `pair`: привязка узла-хранителя (на NAS, Raspberry Pi) к учётной записи
/// по одноразовому коду (задачи 6.1.1, 6.1.2; protocol.md, раздел 4.17).
/// Владелец вводит код, который показывает узел командой `node pair`,
/// сверяет отпечаток ключа узла и подписывает сертификат ключом учётной
/// записи; узел забирает его у координатора.
final class _NodePairCommand extends CliCommand {
  new(super.ctx) {
    argParser.addFlag(
      'yes',
      negatable: false,
      help: 'Подтвердить отпечаток узла без вопроса',
    );
  }

  @override
  String get name => 'pair';

  @override
  String get description =>
      'Привязать узел к учётной записи по одноразовому коду.';

  @override
  Future<int> run() async {
    final a = argResults!;
    if (a.rest.length != 1) {
      throw UsageException('cli node pair <код>', '');
    }
    final code = a.rest.single;
    final config = ctx.config();
    if (config.coordinator == null) {
      throw const CliException(
        'Координатор не настроен: cli config --coordinator URL',
      );
    }
    final crypto = await ctx.crypto();
    final keys = await ctx.unlock();
    try {
      final ops = await ctx.accountOps();
      final client = ops.client(config);
      try {
        final lookup = await client.nodePairLookup(
          pb.NodePairLookupRequest(code: code),
          accountKey: keys.accountSign,
        );
        final nodeId = Uint8List.fromList(lookup.nodeId);
        final nodeDh = Uint8List.fromList(lookup.nodeDh);
        final fingerprint = nodeFingerprint(
          crypto,
          nodeId: nodeId,
          nodeDh: nodeDh,
        );
        ctx.report
          ..info('Узел: ${bytesToHex(nodeId).substring(0, 16)}…')
          ..info('Отпечаток узла: $fingerprint');
        if (!a.flag('yes')) {
          final answer = ctx.console.ask(
            'Отпечаток совпадает с тем, что показывает узел? (да/нет): ',
          );
          if (answer?.trim().toLowerCase() != 'да') {
            throw const CliException('Привязка отменена', ExitCode.cancelled);
          }
        }
        final signed = await NodeCertificates.issue(
          crypto,
          keys,
          nodeId: nodeId,
          nodeDh: nodeDh,
          issuedAt: DateTime.now(),
        );
        await client.nodePairSign(
          pb.NodePairSignRequest(code: code, nodeCertificate: signed),
          accountKey: keys.accountSign,
        );
        ctx.report
          ..info('Сертификат отправлен; узел заберёт его и привяжется.')
          ..result({'nodeId': bytesToHex(nodeId)});
        return ExitCode.ok;
      } finally {
        client.close();
      }
    } finally {
      keys.dispose();
    }
  }
}
