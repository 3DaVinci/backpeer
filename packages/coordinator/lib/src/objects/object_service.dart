import 'dart:typed_data';

import 'package:coordinator/src/db/database.dart';
import 'package:coordinator/src/rpc/call_context.dart';
import 'package:coordinator/src/rpc/errors.dart';
import 'package:fixnum/fixnum.dart';
import 'package:postgres/postgres.dart';
import 'package:protocol/protocol.dart' as pb;

/// Снимки и индексы — зашифрованные блобы учётной записи (задачи 2.5.1,
/// 2.5.2; protocol.md, раздел 4.8). Координатор хранит их непрозрачными;
/// открыто он знает только размер, время и `sequence` снимка, по которому
/// клиент замечает откат (manifest.md, раздел 6).
final class ObjectService {
  new(this._db, {this.maxAccountBytes = 1 << 30, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final Database _db;
  final DateTime Function() _clock;

  /// Объём объектов учётной записи (сумма размеров блобов).
  final int maxAccountBytes;

  /// Предел блоба (manifest.md, раздел 8).
  static const int maxBlobBytes = 8 * 1024 * 1024;

  /// Страница `ListObjects` по умолчанию и наибольшая.
  static const maxListPage = 1000;

  static const _idLength = 32;

  Future<pb.PutObjectResponse> put(
    CallContext context,
    pb.PutObjectRequest request,
  ) async {
    final kind = _kind(request.kind);
    final id = _id(request.objectId);
    final size = request.blob.length;
    if (size == 0) throw _bad('пустой блоб');
    if (size > maxBlobBytes) throw _bad('блоб больше 8 МиБ');
    // uint64 больше 2^63 − 1 приходит отрицательным Int64.
    if (request.sequence.isNegative) throw _bad('sequence слишком велик');
    final sequence = request.sequence.toInt();
    if (kind == pb.ObjectKind.OBJECT_KIND_INDEX && sequence != 0) {
      throw _bad('sequence задаётся только у снимка');
    }
    final accountId = _account(context);
    await _db.transaction((tx) async {
      // Блокировка учётной записи: одновременные записи не превысят предел.
      final usage = await tx.execute(
        Sql.named(
          'SELECT object_bytes FROM accounts WHERE account_id = @a:bytea '
          'FOR UPDATE',
        ),
        parameters: {'a': accountId},
      );
      final used = usage.single.single! as int;
      final old = await tx.execute(
        Sql.named('''
          SELECT size FROM objects
            WHERE account_id = @a:bytea AND kind = @k:int2
              AND object_id = @o:bytea'''),
        parameters: {'a': accountId, 'k': kind.value, 'o': id},
      );
      final replaced = old.isEmpty ? 0 : old.single.single! as int;
      final total = used - replaced + size;
      if (total > maxAccountBytes) {
        throw const RpcException(
          pb.ErrorCode.ERROR_CODE_QUOTA_EXCEEDED,
          'превышен объём объектов учётной записи',
        );
      }
      // Повторная запись того же идентификатора заменяет объект.
      await tx.execute(
        Sql.named(
          '''
          INSERT INTO objects
            (account_id, kind, object_id, blob, size, sequence, stored_at)
          VALUES (@a:bytea, @k:int2, @o:bytea, @b:bytea, @s:int4, @q:int8,
                  @t:timestamptz)
          ON CONFLICT (account_id, kind, object_id) DO UPDATE
            SET blob = excluded.blob, size = excluded.size,
                sequence = excluded.sequence, stored_at = excluded.stored_at''',
        ),
        parameters: {
          'a': accountId,
          'k': kind.value,
          'o': id,
          'b': Uint8List.fromList(request.blob),
          's': size,
          'q': sequence,
          't': _clock(),
        },
      );
      await _setUsage(tx, accountId, total);
    });
    return pb.PutObjectResponse();
  }

  Future<pb.ListObjectsResponse> list(
    CallContext context,
    pb.ListObjectsRequest request,
  ) async {
    final kind = _kind(request.kind);
    final after = request.afterObjectId;
    if (after.isNotEmpty && after.length != _idLength) {
      throw _bad('after_object_id — 32 байта или пусто');
    }
    final limit = request.limit == 0 || request.limit > maxListPage
        ? maxListPage
        : request.limit;
    // bytea сравнивается побайтно: порядок — по возрастанию идентификатора.
    final rows = await _db.run(
      (s) => s.execute(
        Sql.named('''
          SELECT object_id, size,
                 (extract(epoch FROM stored_at) * 1000)::int8, sequence
            FROM objects
            WHERE account_id = @a:bytea AND kind = @k:int2
              AND object_id > @after:bytea
            ORDER BY object_id LIMIT @n:int4'''),
        parameters: {
          'a': _account(context),
          'k': kind.value,
          'after': Uint8List.fromList(after),
          'n': limit + 1,
        },
      ),
    );
    return pb.ListObjectsResponse(
      objects: [
        for (final [
              id as List<int>,
              size as int,
              stored as int,
              sequence as int,
            ]
            in rows.take(limit))
          pb.ObjectInfo(
            objectId: id,
            size: size,
            storedAtUnixMs: Int64(stored),
            sequence: Int64(sequence),
          ),
      ],
      more: rows.length > limit,
    );
  }

  Future<pb.GetObjectResponse> get(
    CallContext context,
    pb.GetObjectRequest request,
  ) async {
    final kind = _kind(request.kind);
    final id = _id(request.objectId);
    final rows = await _db.run(
      (s) => s.execute(
        Sql.named('''
          SELECT blob FROM objects
            WHERE account_id = @a:bytea AND kind = @k:int2
              AND object_id = @o:bytea'''),
        parameters: {'a': _account(context), 'k': kind.value, 'o': id},
      ),
    );
    if (rows.isEmpty) {
      throw const RpcException(
        pb.ErrorCode.ERROR_CODE_NOT_FOUND,
        'объект не найден',
      );
    }
    return pb.GetObjectResponse(blob: rows.single.single! as List<int>);
  }

  /// Отсутствующий объект — успех без изменений.
  Future<pb.DeleteObjectResponse> delete(
    CallContext context,
    pb.DeleteObjectRequest request,
  ) async {
    final kind = _kind(request.kind);
    final id = _id(request.objectId);
    final accountId = _account(context);
    await _db.transaction((tx) async {
      final usage = await tx.execute(
        Sql.named(
          'SELECT object_bytes FROM accounts WHERE account_id = @a:bytea '
          'FOR UPDATE',
        ),
        parameters: {'a': accountId},
      );
      final deleted = await tx.execute(
        Sql.named('''
          DELETE FROM objects
            WHERE account_id = @a:bytea AND kind = @k:int2
              AND object_id = @o:bytea
            RETURNING size'''),
        parameters: {'a': accountId, 'k': kind.value, 'o': id},
      );
      if (deleted.isEmpty) return;
      final used = usage.single.single! as int;
      await _setUsage(tx, accountId, used - (deleted.single.single! as int));
    });
    return pb.DeleteObjectResponse();
  }

  /// Занятый объектами объём учётной записи.
  Future<int> usage(Uint8List accountId) async {
    final rows = await _db.run(
      (s) => s.execute(
        Sql.named(
          'SELECT object_bytes FROM accounts WHERE account_id = @a:bytea',
        ),
        parameters: {'a': accountId},
      ),
    );
    return rows.isEmpty ? 0 : rows.single.single! as int;
  }

  static Future<void> _setUsage(TxSession tx, Uint8List accountId, int bytes) =>
      tx.execute(
        Sql.named(
          'UPDATE accounts SET object_bytes = @b:int8 '
          'WHERE account_id = @a:bytea',
        ),
        parameters: {'a': accountId, 'b': bytes},
      );

  /// Учётная запись устройства, подписавшего запрос.
  static Uint8List _account(CallContext context) =>
      context.caller!.info!.accountId;

  static pb.ObjectKind _kind(pb.ObjectKind kind) => switch (kind) {
    pb.ObjectKind.OBJECT_KIND_SNAPSHOT ||
    pb.ObjectKind.OBJECT_KIND_INDEX => kind,
    _ => throw _bad('неизвестный вид объекта'),
  };

  static Uint8List _id(List<int> id) {
    if (id.length != _idLength) throw _bad('object_id — 32 байта');
    return Uint8List.fromList(id);
  }

  static RpcException _bad(String message) =>
      RpcException(pb.ErrorCode.ERROR_CODE_BAD_REQUEST, message);
}
