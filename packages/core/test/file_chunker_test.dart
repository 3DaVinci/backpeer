import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';
import 'package:test_vectors/test_vectors.dart';

void main() {
  late CryptoProvider crypto;
  late FastCdc cdc;
  late Directory dir;
  setUpAll(() async {
    crypto = await SodiumCryptoProvider.load();
    cdc = FastCdc(GearTable.derive(crypto, SecretBytes(Uint8List(32))));
  });
  setUp(() => dir = Directory.systemTemp.createTempSync('fs-chunk-'));
  tearDown(() => dir.deleteSync(recursive: true));

  File write(String name, Uint8List data) =>
      File('${dir.path}/$name')..writeAsBytesSync(data);

  Future<List<ChunkRead>> chunks(File file, {int? bufferSize}) async => [
    await for (final e in chunkFile(
      file,
      cdc,
      bufferSize: bufferSize ?? 16 * 1024 * 1024,
    ))
      e as ChunkRead,
  ];

  test('пустой файл не даёт чанков', () async {
    expect(await chunks(write('empty', Uint8List(0))), isEmpty);
  });

  test('совпадает с нарезкой в памяти при любом размере окна', () async {
    final data = splitmix64Bytes(7, 40 * 1024 * 1024 + 12345);
    final expected = cdc.chunkLengths(data);
    final file = write('random', data);
    for (final size in [FastCdc.maxSize, FastCdc.maxSize + 4097, 32 << 20]) {
      final got = await chunks(file, bufferSize: size);
      expect(got.map((c) => c.data.length).toList(), expected, reason: '$size');
      var offset = 0;
      for (final c in got) {
        expect(c.offset, offset);
        expect(
          crypto.blake2b256(c.data),
          crypto.blake2b256(
            Uint8List.sublistView(data, offset, offset + c.data.length),
          ),
        );
        offset += c.data.length;
      }
    }
  });

  test('окно меньше maxSize — ArgumentError', () {
    expect(
      () => chunkFile(write('x', Uint8List(1)), cdc, bufferSize: 1024),
      throwsArgumentError,
    );
  });

  test('файл изменился во время чтения — перезапуск', () async {
    final data = splitmix64Bytes(8, 24 * 1024 * 1024);
    final file = write('changing', data);
    final events = <FileChunkEvent>[];
    var appended = false;
    await for (final e in chunkFile(file, cdc)) {
      events.add(e);
      if (!appended) {
        appended = true;
        file.writeAsBytesSync([1, 2, 3], mode: FileMode.append);
      }
    }
    final restart = events.indexWhere((e) => e is ReadRestarted);
    expect(restart, greaterThan(0));
    expect((events[restart] as ReadRestarted).attempt, 2);
    final second = events.skip(restart + 1).cast<ChunkRead>();
    expect(second.fold(0, (sum, c) => sum + c.data.length), data.length + 3);
  });

  test('мелкий файл вырос больше буфера во время чтения', () async {
    // Буфер мелкого файла — по его размеру; после роста нарезка по
    // неполному окну отбрасывается, вторая попытка режет как эталон.
    final data = splitmix64Bytes(10, 1000);
    final grown = splitmix64Bytes(11, 3 * 1024 * 1024);
    final file = write('small', data);
    var stamps = 0;
    final events = await chunkFile(
      file,
      cdc,
      stamp: () {
        // Рост между снятием штампа и открытием файла.
        if (stamps++ == 0) {
          final before = (size: data.length, mtimeNs: 0, ctimeNs: 0);
          file.writeAsBytesSync([...data, ...grown]);
          return before;
        }
        return (size: data.length + grown.length, mtimeNs: 1, ctimeNs: 1);
      },
    ).toList();
    final restart = events.indexWhere((e) => e is ReadRestarted);
    expect(restart, greaterThan(0));
    final second = events.skip(restart + 1).cast<ChunkRead>().toList();
    expect(
      second.map((c) => c.data.length).toList(),
      cdc.chunkLengths(Uint8List.fromList([...data, ...grown])),
    );
  });

  test('файл меняется постоянно — SourceChangedException', () async {
    final file = write('always', splitmix64Bytes(9, 12 * 1024 * 1024));
    var n = 0;
    await expectLater(
      () async {
        await for (final e in chunkFile(file, cdc, maxAttempts: 2)) {
          if (e is ChunkRead) {
            file.writeAsBytesSync([n++ & 0xFF], mode: FileMode.append);
          }
        }
      }(),
      throwsA(
        isA<SourceChangedException>().having((e) => e.attempts, 'attempts', 2),
      ),
    );
  });

  // Долгий тест: FS_LARGE_TESTS=1 dart test test/file_chunker_test.dart
  // Размер — FS_LARGE_FILE_GIB (по умолчанию 5, больше 4 ГиБ).
  test(
    'большой разрежённый файл: память в пределах окна',
    () async {
      final gib = int.parse(Platform.environment['FS_LARGE_FILE_GIB'] ?? '5');
      final size = gib << 30;
      final file = File('${dir.path}/large');
      final raf = file.openSync(mode: FileMode.write)
        ..setPositionSync(size - 1)
        ..writeByteSync(1)
        ..closeSync();
      expect(raf, isNotNull);
      const window = 16 * 1024 * 1024;
      final baseline = ProcessInfo.currentRss;
      var peak = baseline;
      var total = 0;
      final watch = Stopwatch()..start();
      await for (final e in chunkFile(file, cdc)) {
        total += (e as ChunkRead).data.length;
        final rss = ProcessInfo.currentRss;
        if (rss > peak) peak = rss;
      }
      expect(total, size);
      final growth = peak - baseline;
      printOnFailure('рост RSS ${growth >> 20} МиБ');
      stdout.writeln(
        '$gib ГиБ: ${watch.elapsed.inSeconds} с, '
        'рост RSS ${growth >> 20} МиБ',
      );
      expect(growth, lessThan(window + 96 * 1024 * 1024));
    },
    skip: Platform.environment['FS_LARGE_TESTS'] == '1'
        ? false
        : 'долгий тест, включается FS_LARGE_TESTS=1',
    timeout: const Timeout(Duration(minutes: 30)),
  );
}
