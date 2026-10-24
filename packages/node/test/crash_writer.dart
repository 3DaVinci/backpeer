// Запись фрагментов, которую тест хранилища убивает SIGKILL (задача
// 3.2.1): обрыв питания посреди записи не должен оставить битого фрагмента
// под рабочим именем.
//
//   dart run test/crash_writer.dart <папка данных> <точка> <зерно>
//
// Точка — где остановиться и ждать убийства, напечатав её имя:
// `writing` — записана половина фрагмента; `received`, `journaled`,
// `installed` — стадии FragmentStorage; `loop` — писать фрагменты с
// зёрнами <зерно>, <зерно> + 1, … без остановки, печатая `stored <hex>`.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:node/node.dart';

import 'support.dart';

Future<void> main(List<String> args) async {
  final [dir, point, seedText] = args;
  final crypto = await SodiumCryptoProvider.load();
  Future<void> hang(String name) async {
    stdout.writeln(name);
    await stdout.flush();
    await Completer<void>().future;
  }

  final storage = FragmentStorage.open(
    dir,
    crypto: crypto,
    quotaBytes: 1 << 40,
    freeReserveBytes: 0,
    onStage: (stage) async {
      if (stage == point) await hang(stage);
    },
  );
  for (var seed = int.parse(seedText); ; seed++) {
    final fragment = testFragment(crypto, seed: seed, blobLength: 1 << 20);
    final bytes = fragment.bytes;
    final id = fragmentIdOf(crypto, fragment);
    final incoming = await storage.beginPut(
      fragmentId: id,
      size: bytes.length,
      accountId: Uint8List(32),
    );
    for (var offset = 0; offset < bytes.length; offset += 61440) {
      final end = offset + 61440 < bytes.length ? offset + 61440 : bytes.length;
      await incoming.add(Uint8List.sublistView(bytes, offset, end));
      if (point == 'writing' && end * 2 >= bytes.length) await hang(point);
    }
    await incoming.commit();
    if (point != 'loop') await hang('done');
    stdout.writeln('stored ${bytesToHex(id)}');
  }
}
