import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  test('сообщение ошибки формата', () {
    const e = DataFormatException(
      object: 'blob',
      problem: FormatProblem.unsupportedVersion,
      detail: 'версия 7',
      offset: 4,
    );
    expect(e.message, 'blob: неподдерживаемая версия (версия 7), смещение 4');
    expect('$e', e.message);
  });

  test('сообщение ошибки целостности с коротким идентификатором', () {
    final e = IntegrityException(
      object: 'фрагмент',
      check: IntegrityCheck.merkleRoot,
      objectId: Uint8List.fromList(List.generate(32, (i) => i)),
    );
    expect(
      e.message,
      'фрагмент 0001020304050607: не сошлась проверка (корень Меркла)',
    );
  });

  test('сообщение ошибки хранилища', () {
    const e = StorageException(
      location: '/nodes/03',
      problem: StorageProblem.unavailable,
      operation: 'put',
    );
    expect(e.message, '/nodes/03 (put): недоступно');
  });

  test('все ошибки core — подтипы CoreException', () {
    String kind(CoreException e) => switch (e) {
      DataFormatException() => 'format',
      IntegrityException() => 'integrity',
      InsufficientShardsException() => 'shards',
      StorageException() => 'storage',
      SourceChangedException() => 'changed',
    };
    expect(
      kind(const InsufficientShardsException(available: 3, required: 4)),
      'shards',
    );
  });

  test('Reed–Solomon сообщает о нехватке фрагментов', () {
    final coder = ReedSolomon(2, 2);
    final shards = <Uint8List?>[Uint8List(4), null, null, null];
    expect(
      () => coder.reconstruct(shards),
      throwsA(
        isA<InsufficientShardsException>()
            .having((e) => e.available, 'available', 1)
            .having((e) => e.required, 'required', 2),
      ),
    );
  });
}
