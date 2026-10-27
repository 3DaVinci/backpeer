import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:node/src/storage/fragment_files.dart';
import 'package:node/src/storage/fragment_storage.dart';
import 'package:protocol/protocol.dart' as pb;

/// Ответ на команду аудита координатора (задача 4.1.2; protocol.md,
/// раздел 4.13): блок фрагмента и путь Меркла из [storage]. Отказ —
/// [CoordinatorException] с кодом для ответа `Error` в канале:
/// `fragment_id` не 32 байта или блока нет — `BAD_REQUEST`; фрагмента нет
/// или он повреждён — `NOT_FOUND`.
Future<pb.AuditReply> answerAudit(
  FragmentStorage storage,
  pb.AuditCommand command,
) async {
  if (command.fragmentId.length != 32) {
    throw const CoordinatorException(
      pb.ErrorCode.ERROR_CODE_BAD_REQUEST,
      'fragment_id — 32 байта',
    );
  }
  try {
    final proof = await storage.prove(
      Uint8List.fromList(command.fragmentId),
      command.blockIndex,
    );
    return pb.AuditReply(block: proof.block, path: proof.path);
  } on FragmentStorageException catch (e) {
    throw CoordinatorException(e.code, e.message);
  }
}
