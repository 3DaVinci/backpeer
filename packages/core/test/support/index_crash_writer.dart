// Вспомогательная программа для local_index_test: пишет сегменты в
// открытой транзакции и ждёт, пока её убьют (SIGKILL) до коммита.

import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';

Future<void> main(List<String> args) async {
  final index = LocalIndex.open(args[0]);
  index.transaction(() {
    for (var i = 0; i < 100; i++) {
      index.addSegment(
        SegmentEntry(
          segmentId: Uint8List(32)..[0] = 100 + i,
          k: 1,
          n: 2,
          blobLength: 80,
          shardSize: 64,
          fragmentIds: [Uint8List(32), Uint8List(32)],
          chunks: const [],
        ),
      );
    }
    stdout.writeln('ready');
    // Синхронное ожидание внутри транзакции: коммита не будет.
    sleep(const Duration(minutes: 5));
  });
}
