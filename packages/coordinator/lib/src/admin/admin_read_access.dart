import 'package:coordinator/src/admin/admin_access.dart';
import 'package:coordinator/src/db/database.dart';
import 'package:postgres/postgres.dart';

/// Права роли веб-панели оператора (ADR-007, `docs/ops/admin.md`): только
/// чтение метаданных, которые координатор и так знает. Ни KeyBundle, ни
/// `auth_verifier`, ни сертификатов, ни блобов, ни `server_secrets`.
///
/// Роль создаёт оператор; права выдаёт `coordinator migrate` (владелец
/// схемы), если роль существует. Отдельная роль нужна, чтобы у процесса
/// панели не было прав координатора или администратора: панель по
/// решению 16.11.2026 работает только на просмотр.
abstract final class AdminReadAccess {
  /// Имя роли по умолчанию (`admin.read_role`).
  static const defaultRole = 'fs_admin_web';

  static final _name = RegExp(r'^[a-z_][a-z0-9_]{0,62}$');

  /// Выдаёт роли [role] права только на чтение; повторный вызов ничего не
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
          '''
            GRANT SELECT (device_sign, account_id, created_at, revoked_at,
                          revocation_seq)
              ON devices TO $role''',
          '''
            GRANT SELECT (node_id, account_id, registered_at, removed_at,
                          capacity_bytes, used_bytes, assigned_bytes,
                          free_bytes, endpoints, versions, software, subnet,
                          last_heartbeat_at, availability, excluded_at,
                          excluded_reason, relay, relay_until,
                          audits_passed, audits_failed, last_audit_at,
                          audit_window_failures, audit_latency_ms,
                          lost_at, repair_suspended_until, leaving_at,
                          reconcile_at, country, city, latitude, longitude,
                          geo_at)
              ON nodes TO $role''',
          'GRANT SELECT ON node_uptime TO $role',
          '''
            GRANT SELECT (account_id, kind, object_id, size, sequence,
                          stored_at)
              ON objects TO $role''',
          'GRANT SELECT ON segments TO $role',
          '''
            GRANT SELECT (account_id, segment_id, idx, fragment_id, node_id,
                          stored, damaged_at, audit_failed_at, audited_at)
              ON fragments TO $role''',
          'GRANT SELECT ON relay_usage, relay_reports, traffic_daily TO $role',
          'GRANT SELECT ON audits TO $role',
          'GRANT SELECT ON repair_jobs, repair_targets TO $role',
          '''
          GRANT SELECT ON credit_accounts, credit_ledger, economy_runs
             TO $role''',
          'GRANT SELECT ON admin_audit TO $role',
        ]) {
          await tx.execute(statement);
        }
        // Даже если права выдали вручную шире, панель ничего не меняет.
        for (final table in [
          'accounts',
          'devices',
          'nodes',
          'node_uptime',
          'objects',
          'segments',
          'fragments',
          'relay_usage',
          'relay_reports',
          'traffic_daily',
          'audits',
          'repair_jobs',
          'repair_targets',
          'credit_accounts',
          'credit_ledger',
          'economy_runs',
          'admin_audit',
        ]) {
          await tx.execute(
            'REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON $table FROM $role',
          );
        }
        return true;
      });

  static Future<bool> roleExists(Session s, String role) async {
    final rows = await s.execute(
      Sql.named('SELECT 1 FROM pg_roles WHERE rolname = @r:text'),
      parameters: {'r': role},
    );
    return rows.isNotEmpty;
  }

  /// Текущий пользователь базы входит в роль [role]; иначе
  /// [AdminAccessException] с объяснением.
  static Future<void> check(Database db, String role) => db.run((s) async {
    if (!await roleExists(s, role)) {
      throw AdminAccessException(
        'в базе нет роли $role: создайте её и выполните coordinator migrate '
        '(docs/ops/admin.md, раздел «Роль только для чтения»)',
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
        'пользователь базы $user не входит в роль $role: панель запускается '
        'под ролью только для чтения (docs/ops/admin.md)',
      );
    }
  });
}
