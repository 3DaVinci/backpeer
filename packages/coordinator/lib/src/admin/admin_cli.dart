import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:coordinator/src/admin/admin_access.dart';
import 'package:coordinator/src/admin/admin_service.dart';
import 'package:postgres/postgres.dart';

/// Ввод и вывод команд администратора.
abstract interface class AdminConsole {
  void out(String line);
  void err(String line);

  /// Ответ на вопрос; `null` — ввода нет (не терминал).
  String? ask(String prompt);
}

/// Консоль процесса.
final class StdAdminConsole implements AdminConsole {
  const new();

  @override
  void out(String line) => stdout.writeln(line);

  @override
  void err(String line) => stderr.writeln(line);

  @override
  String? ask(String prompt) {
    if (!stdin.hasTerminal) return null;
    stderr.write(prompt);
    return stdin.readLineSync();
  }
}

/// Коды возврата `coordinator admin` (sysexits).
abstract final class AdminExit {
  static const ok = 0;
  static const error = 1;
  static const usage = 64;
  static const noPermission = 77;
}

const adminUsage = '''
Администрирование координатора (docs/ops/coordinator.md, «Администрирование»).
Запускается на сервере с настройками администратора (роль базы fs_admin).

  coordinator admin account find <имя | ключ>
  coordinator admin account show <учётная запись>
  coordinator admin account block <учётная запись> --reason ТЕКСТ [--yes]
  coordinator admin account unblock <учётная запись> --reason ТЕКСТ [--yes]
  coordinator admin device revoke <устройство> --reason ТЕКСТ [--yes]
  coordinator admin node list [--account <учётная запись>]
  coordinator admin node show <узел>
  coordinator admin node exclude <узел> --reason ТЕКСТ [--yes]
  coordinator admin node include <узел> --reason ТЕКСТ [--yes]
  coordinator admin stats
  coordinator admin audit [--limit N]

Учётная запись — имя для входа или 64 hex-символа (account_id, ключ
устройства или узла); устройство и узел — не меньше 8 hex-символов ключа.
--json — результат одним объектом JSON.
''';

/// Разбор `coordinator admin …` поверх [service] (задача 2.10). Изменяющие
/// команды требуют `--reason` и подтверждения (`--yes` или «да» в
/// терминале) и пишутся в журнал.
Future<int> runAdmin(
  List<String> arguments, {
  required AdminService service,
  required String osUser,
  AdminConsole console = const StdAdminConsole(),
}) async {
  final parser = ArgParser()
    ..addFlag('json', negatable: false)
    ..addFlag('yes', abbr: 'y', negatable: false)
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addOption('reason')
    ..addOption('account')
    ..addOption('limit', defaultsTo: '50');
  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    console.err('${e.message}\n\n$adminUsage');
    return AdminExit.usage;
  }
  if (args.flag('help') || args.rest.isEmpty) {
    console.out(adminUsage);
    return args.flag('help') ? AdminExit.ok : AdminExit.usage;
  }
  final json = args.flag('json');

  AdminActor actor(String what) {
    final reason = args.option('reason')?.trim() ?? '';
    if (reason.isEmpty) {
      throw const _Usage('изменяющей команде нужна причина: --reason');
    }
    if (!args.flag('yes')) {
      final answer = console.ask('$what. Выполнить? (да/нет): ');
      if (answer == null) {
        throw const _Usage('нет терминала для подтверждения: добавьте --yes');
      }
      if (answer.trim().toLowerCase() != 'да') throw const _Cancelled();
    }
    return AdminActor(osUser: osUser, reason: reason);
  }

  try {
    final result = switch (args.rest) {
      ['account', 'find', final q] => await service.findAccounts(q),
      ['account', 'show', final q] => await service.showAccount(q),
      ['account', 'block', final q] => await service.setBlocked(
        q,
        blocked: true,
        actor: actor('Заблокировать учётную запись $q'),
      ),
      ['account', 'unblock', final q] => await service.setBlocked(
        q,
        blocked: false,
        actor: actor('Разблокировать учётную запись $q'),
      ),
      ['device', 'revoke', final d] => await service.revokeDevice(
        d,
        actor: actor('Отозвать устройство $d'),
      ),
      ['node', 'list'] => await service.listNodes(
        account: args.option('account'),
      ),
      ['node', 'show', final n] => await service.showNode(n),
      ['node', 'exclude', final n] => await service.setExcluded(
        n,
        excluded: true,
        actor: actor('Исключить узел $n из размещения'),
      ),
      ['node', 'include', final n] => await service.setExcluded(
        n,
        excluded: false,
        actor: actor('Вернуть узел $n в размещение'),
      ),
      ['stats'] => await service.stats(),
      ['audit'] => await service.audit(
        limit: (int.tryParse(args.option('limit')!) ?? 50).clamp(1, 10000),
      ),
      _ => throw const _Usage('неизвестная команда'),
    };
    if (json) {
      console.out(jsonEncode(result));
    } else {
      _print(console, result, '');
    }
    return AdminExit.ok;
  } on _Usage catch (e) {
    console.err('${e.message}\n\n$adminUsage');
    return AdminExit.usage;
  } on _Cancelled {
    console.err('Отменено.');
    return AdminExit.error;
  } on AdminException catch (e) {
    console.err('Ошибка: ${e.message}');
    return AdminExit.error;
  } on AdminAccessException catch (e) {
    console.err('Нет прав: ${e.message}');
    return AdminExit.noPermission;
  } on ServerException catch (e) {
    if (e.code == '42501') {
      console.err(
        'Нет прав в базе: ${e.message}. Нужна роль администратора и права '
        'из coordinator migrate (docs/ops/coordinator.md)',
      );
      return AdminExit.noPermission;
    }
    rethrow;
  }
}

/// Копия записи журнала в журнал ОС: `logger` (syslog, journald).
void systemJournal(AuditRecord record) {
  Process.runSync('logger', [
    '-t',
    'fs-coordinator-admin',
    '-p',
    'authpriv.notice',
    '--',
    jsonEncode(record),
  ]);
}

/// Пользователь ОС, от имени которого выполняется команда.
String osUserName(Map<String, String> env) =>
    env['SUDO_USER'] ?? env['USER'] ?? env['LOGNAME'] ?? 'unknown';

void _print(AdminConsole console, Object? value, String indent) {
  switch (value) {
    case final List<Object?> list:
      if (list.isEmpty) console.out('$indent(нет)');
      for (final item in list) {
        if (item is Map<String, Object?>) {
          final fields = [
            for (final MapEntry(:key, :value) in item.entries)
              if (value != null && value is! Map && value is! List)
                '$key=$value',
          ];
          console.out('$indent– ${fields.join('  ')}');
        } else {
          console.out('$indent– $item');
        }
      }
    case final Map<String, Object?> map:
      for (final MapEntry(:key, :value) in map.entries) {
        if (value is Map || value is List) {
          console.out('$indent$key:');
          _print(console, value, '$indent  ');
        } else {
          console.out('$indent$key: ${value ?? '—'}');
        }
      }
    default:
      console.out('$indent$value');
  }
}

final class _Usage implements Exception {
  const new(this.message);

  final String message;
}

final class _Cancelled implements Exception {
  const new();
}
