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
    SELECT 0, account_id, false FROM accounts WHERE account_id = @k:bytea
    UNION ALL
    SELECT 1, account_id, revoked_at IS NOT NULL
      FROM devices WHERE device_sign = @k:bytea
    UNION ALL
    SELECT 2, account_id, removed_at IS NOT NULL
      FROM nodes WHERE node_id = @k:bytea
    LIMIT 1''');

  @override
  Future<KeyInfo?> lookup(Uint8List publicKey) async {
    final rows = await _db.run(
      (s) => s.execute(_query, parameters: {'k': publicKey}),
    );
    if (rows.isEmpty) return null;
    final [kind as int, accountId as List<int>, revoked as bool] = rows.single;
    return KeyInfo(
      kind: _kinds[kind],
      accountId: Uint8List.fromList(accountId),
      revoked: revoked,
    );
  }
}
