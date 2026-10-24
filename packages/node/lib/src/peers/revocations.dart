import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:logging/logging.dart';
import 'package:node/src/daemon/log.dart';
import 'package:node/src/storage/fragment_index.dart';
import 'package:protocol/protocol.dart' as pb;

/// Отозванные устройства (protocol.md, раздел 4.7; задача 3.3.2). Узел
/// получает отзывы от координатора (`ListRevocations`), проверяет подпись
/// каждого сам и хранит их в индексе: после перезапуска демона отозванное
/// устройство по-прежнему не проходит рукопожатие.
///
/// Отзыв с неверной подписью или полями пропускается с предупреждением в
/// журнале: узел верит только подписи учётной записи, а не координатору.
final class RevocationList implements RevokedDevices {
  new(this._index, this._crypto) {
    for (final key in _index.revokedDeviceKeys()) {
      _revoked.add(bytesToHex(key));
    }
  }

  final FragmentIndex _index;
  final CryptoProvider _crypto;
  final Set<String> _revoked = {};

  static final _log = Logger('revocations');

  /// Наибольшая страница `ListRevocations` (protocol.md, раздел 4.7).
  static const pageLimit = 1000;

  int get count => _revoked.length;

  /// Номер последнего полученного отзыва.
  int get sequence => _index.revocationSequence;

  @override
  bool isRevoked(Uint8List deviceSign) =>
      _revoked.contains(bytesToHex(deviceSign));

  /// Дочитывает список отзывов у координатора до конца. Ошибки связи —
  /// [CoordinatorException]; полученные до неё страницы уже сохранены.
  /// Возвращает число новых отзывов.
  Future<int> sync(CoordinatorClient client, Ed25519KeyPair nodeKey) async {
    var added = 0;
    while (true) {
      final response = await client.listRevocations(
        pb.ListRevocationsRequest(
          afterSequence: Int64(sequence),
          limit: pageLimit,
        ),
        nodeKey: nodeKey,
      );
      added += await apply(response.revocations);
      if (!response.more || response.revocations.isEmpty) return added;
    }
  }

  /// Проверяет и сохраняет страницу отзывов. Возвращает число новых.
  Future<int> apply(List<pb.RevocationEntry> entries) async {
    if (entries.isEmpty) return 0;
    final valid = <RevokedDevice>[];
    var last = sequence;
    for (final entry in entries) {
      final seq = entry.sequence.toInt();
      if (seq <= last) {
        // Координатор обязан отдавать номера по возрастанию.
        _log.warning(LogEvent('revocation_out_of_order', {'sequence': seq}));
        continue;
      }
      last = seq;
      try {
        final r = await DeviceCertificates.openRevocation(
          _crypto,
          entry.revocation,
        );
        valid.add(
          RevokedDevice(
            deviceSign: Uint8List.fromList(r.deviceSign),
            accountId: Uint8List.fromList(r.accountId),
            revokedAt: DateTime.fromMillisecondsSinceEpoch(
              r.revokedAtUnixMs.toInt(),
              isUtc: true,
            ),
            sequence: seq,
          ),
        );
      } on CoreException catch (e) {
        _log.warning(
          LogEvent('revocation_rejected', {
            'sequence': seq,
            'reason': e.message,
          }),
        );
      }
    }
    _index.addRevocations(valid, last);
    var added = 0;
    for (final r in valid) {
      if (_revoked.add(bytesToHex(r.deviceSign))) added++;
    }
    if (added > 0) {
      _log.info(LogEvent('revocations_received', {'devices': added}));
    }
    return added;
  }
}
