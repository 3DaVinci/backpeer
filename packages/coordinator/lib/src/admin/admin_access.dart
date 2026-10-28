import 'package:coordinator/src/db/database.dart';
import 'package:postgres/postgres.dart';

/// Права роли администратора (задача 2.10.1; ADR-007): чтение метаданных,
/// которые координатор и так видит, без KeyBundle, `auth_verifier`,
/// сертификатов и блобов (модель угроз, К-2); изменение только полей
/// блокировки, отзыва и исключения; журнал — только добавление.
///
/// Права выдаёт владелец схемы (роль координатора) после миграций:
/// `coordinator migrate`, если роль существует. Создаёт роль оператор
/// (`docs/ops/coordinator.md`, раздел «Администрирование»).
abstract final class AdminAccess {
  /// Имя роли по умолчанию (`admin.role`).
  static const defaultRole = 'fs_admin';

  static final _name = RegExp(r'^[a-z_][a-z0-9_]{0,62}$');

  /// Существует ли роль [role].
  static Future<bool> roleExists(Session s, String role) async {
    final rows = await s.execute(
      Sql.named('SELECT 1 FROM pg_roles WHERE rolname = @r:text'),
      parameters: {'r': role},
    );
    return rows.isNotEmpty;
  }

  /// Выдаёт роли [role] права администратора; повторный вызов ничего не
  /// меняет. Роли нет — `false`.
  static Future<bool> grant(Database db, String role) =>
      db.transaction((tx) async {
        if (!_name.hasMatch(role)) {
          throw ArgumentError.value(role, 'role', 'недопустимое имя роли');
        }
        if (!await roleExists(tx, role)) return false;
        for (final statement in [
          'GRANT USAGE ON SCHEMA public TO $role',
          'GRANT SELECT ON schema_migrations TO $role',
          'GRANT SELECT ON admin_accounts TO $role',
          'GRANT SELECT (account_id, login, blocked_at) ON accounts TO $role',
          'GRANT UPDATE (blocked_at, blocked_reason) ON accounts TO $role',
          '''
            GRANT SELECT (device_sign, account_id, created_at, revoked_at,
                          revocation_seq) ON devices TO $role''',
          'GRANT UPDATE (revoked_at) ON devices TO $role',
          '''
            GRANT SELECT (node_id, account_id, registered_at, removed_at,
                          capacity_bytes, used_bytes, assigned_bytes,
                          endpoints, versions, software, subnet,
                          last_heartbeat_at, availability, excluded_at,
                          excluded_reason, relay, relay_until,
                          audits_passed, audits_failed, last_audit_at,
                          audit_window_failures, audit_latency_ms,
                          lost_at, repair_suspended_until, leaving_at,
                          reconcile_at)
              ON nodes TO $role''',
          'GRANT UPDATE (excluded_at, excluded_reason) ON nodes TO $role',
          '''
            GRANT SELECT (account_id, kind, object_id, size, sequence,
                          stored_at) ON objects TO $role''',
          'GRANT SELECT ON segments TO $role',
          '''
            GRANT SELECT (account_id, segment_id, idx, node_id, stored)
              ON fragments TO $role''',
          // Метрики relay и трафика (задача 3.8.3): объёмы без содержимого.
          'GRANT SELECT ON relay_usage, relay_reports, traffic_daily TO $role',
          // Итоги аудитов (задача 4.1.3): какие блоки и когда проверялись.
          'GRANT SELECT ON audits TO $role',
          // Задания ремонта (задача 4.3.6): исполнители, узлы, трафик.
          'GRANT SELECT ON repair_jobs, repair_targets TO $role',
          'GRANT SELECT, INSERT ON admin_audit TO $role',
          'GRANT USAGE ON SEQUENCE admin_audit_id_seq TO $role',
          // На случай прав, выданных вручную: журнал роль не меняет.
          'REVOKE UPDATE, DELETE, TRUNCATE ON admin_audit FROM $role',
        ]) {
          await tx.execute(statement);
        }
        return true;
      });

  /// Текущий пользователь базы входит в роль [role]; иначе
  /// [AdminAccessException] с объяснением.
  static Future<void> check(Database db, String role) => db.run((s) async {
    if (!await roleExists(s, role)) {
      throw AdminAccessException(
        'в базе нет роли $role: создайте её и выполните coordinator migrate '
        '(docs/ops/coordinator.md, раздел «Администрирование»)',
      );
    }
    final rows = await s.execute(
      Sql.named(
        "SELECT current_user, pg_has_role(current_user, @r:text, 'MEMBER')",
      ),
      parameters: {'r': role},
    );
    final [user as String, member as bool] = rows.single;
    if (!member) {
      throw AdminAccessException(
        'пользователь базы $user не входит в роль $role: администрирование '
        'выполняется с настройками администратора (database.user)',
      );
    }
  });
}

/// Нет прав администратора.
final class AdminAccessException implements Exception {
  const new(this.message);

  final String message;

  @override
  String toString() => 'AdminAccessException: $message';
}
