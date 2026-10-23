import 'dart:typed_data';

import 'package:coordinator/src/auth/key_directory.dart';
import 'package:coordinator/src/db/database.dart';
import 'package:postgres/postgres.dart';

/// Справочник ключей по таблицам `accounts`, `devices`, `nodes`.
final class PostgresKeyDirectory implements KeyDirectory {
  const new(this._db);

  final Database _db;

  // Порядок — как первый столбец запроса.
  static const List<KeyKind> _kinds = [
    KeyKind.account,
    KeyKind.device,
    KeyKind.node,
  ];

  static final Sql _query = Sql.named('''
    SELECT 0, account_id, false, blocked_at IS NOT NULL
      FROM accounts WHERE account_id = @k:bytea
    UNION ALL
    SELECT 1, d.account_id, d.revoked_at IS NOT NULL, a.blocked_at IS NOT NULL
      FROM devices d JOIN accounts a USING (account_id)
      WHERE d.device_sign = @k:bytea
    UNION ALL
    SELECT 2, n.account_id, n.removed_at IS NOT NULL, a.blocked_at IS NOT NULL
      FROM nodes n JOIN accounts a USING (account_id)
      WHERE n.node_id = @k:bytea
    LIMIT 1''');

  @override
  Future<KeyInfo?> lookup(Uint8List publicKey) async {
    final rows = await _db.run(
      (s) => s.execute(_query, parameters: {'k': publicKey}),
    );
    if (rows.isEmpty) return null;
    final [
      kind as int,
      accountId as List<int>,
      revoked as bool,
      blocked as bool,
    ] = rows.single;
    return KeyInfo(
      kind: _kinds[kind],
      accountId: Uint8List.fromList(accountId),
      revoked: revoked,
      blocked: blocked,
    );
  }
}
