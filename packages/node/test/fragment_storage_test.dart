// Хранилище фрагментов узла: раскладка и атомарная запись (3.2.1), индекс
// и талоны (3.2.2), квота и место (3.2.3).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:node/node.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';

import 'support.dart';

Matcher _failsWith(pb.ErrorCode code) => throwsA(
  isA<FragmentStorageException>().having((e) => e.code, 'code', code),
);

void main() {
  late CryptoProvider crypto;
  late Directory dir;
  final open = <FragmentStorage>[];
  setUpAll(() async => crypto = await SodiumCryptoProvider.load());
  setUp(() => dir = Directory.systemTemp.createTempSync('fs-node-storage-'));
  tearDown(() async {
    for (final s in open) {
      await s.close();
    }
    open.clear();
    dir.deleteSync(recursive: true);
  });

  final account = Uint8List(32)..[0] = 1;
  final stranger = Uint8List(32)..[0] = 2;

  FragmentStorage storage({
    int quota = 1 << 40,
    int reserve = 0,
    int? Function(String)? disk,
    DateTime Function()? clock,
  }) {
    final s = FragmentStorage.open(
      dir.path,
      crypto: crypto,
      quotaBytes: quota,
      freeReserveBytes: reserve,
      diskAvailable: disk ?? (_) => null,
      clock: clock,
    );
    open.add(s);
    return s;
  }

  Future<void> reopen(FragmentStorage s) async {
    await s.close();
    open.remove(s);
  }

  /// Загружает [bytes] частями по 61 440 байт (как `FragmentData`).
  Future<FragmentRecord> put(
    FragmentStorage s,
    Uint8List bytes, {
    Uint8List? id,
    int? size,
    Uint8List? owner,
  }) async {
    final incoming = await s.beginPut(
      fragmentId: id ?? crypto.blake2b256(bytes.sublist(0, 96)),
      size: size ?? bytes.length,
      accountId: owner ?? account,
    );
    for (var offset = 0; offset < bytes.length; offset += 61440) {
      await incoming.add(
        Uint8List.sublistView(bytes, offset, min(offset + 61440, bytes.length)),
      );
    }
    return await incoming.commit();
  }

  List<String> filesUnder(Directory root) => [
    for (final f in root.listSync(recursive: true))
      if (f is File) f.path.substring(root.path.length + 1),
  ]..sort();

  group('раскладка и запись (3.2.1)', () {
    test('фрагмент ложится в ab/cd/<id>.frag и читается обратно', () async {
      final s = storage();
      final f = testFragment(crypto);
      final id = fragmentIdOf(crypto, f);
      final hex = bytesToHex(id);
      final record = await put(s, f.bytes);
      expect(record.state, FragmentState.stored);
      expect(record.accountId, account);
      expect(record.size, f.bytes.length);
      expect(record.bodyRoot, f.header.bodyRoot);
      expect(filesUnder(s.files.root), [
        '${hex.substring(0, 2)}/${hex.substring(2, 4)}/$hex.frag',
      ], reason: 'временных файлов не осталось');
      final read = await s
          .openRead(id)
          .fold<BytesBuilder>(BytesBuilder(), (b, c) => b..add(c));
      expect(read.takeBytes(), f.bytes);
      expect(s.usedBytes, f.bytes.length);
      expect(s.fragmentCount, 1);
    });

    test('чужой, обрезанный, лишний и испорченный фрагмент отклоняются, '
        'не оставляя следов', () async {
      final s = storage();
      final f = testFragment(crypto);
      final bytes = f.bytes;
      final id = fragmentIdOf(crypto, f);

      // Талон на другой фрагмент: отказ сразу после заголовка.
      final other = await s.beginPut(
        fragmentId: crypto.randomBytes(32),
        size: bytes.length,
        accountId: account,
      );
      await expectLater(
        () => other.add(bytes.sublist(0, 100)),
        _failsWith(pb.ErrorCode.ERROR_CODE_INTEGRITY_FAILED),
      );

      // Размер в талоне не сходится с заголовком.
      await expectLater(
        () => put(s, bytes, size: bytes.length + 64),
        _failsWith(pb.ErrorCode.ERROR_CODE_BAD_REQUEST),
      );

      // Больше обещанного.
      final longer = Uint8List(bytes.length + 1)..setAll(0, bytes);
      await expectLater(
        () => put(s, longer, id: id, size: bytes.length),
        _failsWith(pb.ErrorCode.ERROR_CODE_BAD_REQUEST),
      );

      // Обрыв: меньше обещанного.
      final short = await s.beginPut(
        fragmentId: id,
        size: bytes.length,
        accountId: account,
      );
      await short.add(bytes.sublist(0, 1000));
      await expectLater(
        short.commit,
        _failsWith(pb.ErrorCode.ERROR_CODE_BAD_REQUEST),
      );

      // Испорченное тело: корень дерева не сходится.
      final broken = Uint8List.fromList(bytes)..[bytes.length - 1] ^= 1;
      await expectLater(
        () => put(s, broken),
        _failsWith(pb.ErrorCode.ERROR_CODE_INTEGRITY_FAILED),
      );

      // Испорченный заголовок.
      final badHeader = Uint8List.fromList(bytes)..[0] ^= 1;
      await expectLater(
        () => put(s, badHeader),
        _failsWith(pb.ErrorCode.ERROR_CODE_BAD_REQUEST),
      );

      expect(filesUnder(s.files.root), isEmpty);
      expect(s.record(id), isNull);
      expect(s.usedBytes, 0);
      expect(s.incomingCount, 0);
      await put(s, bytes);
      expect(s.fragmentCount, 1);
    });

    test(
      'повтор — ALREADY_EXISTS, одновременный приём — UNAVAILABLE',
      () async {
        final s = storage();
        final f = testFragment(crypto);
        final id = fragmentIdOf(crypto, f);
        final first = await s.beginPut(
          fragmentId: id,
          size: f.bytes.length,
          accountId: account,
        );
        await expectLater(
          () => s.beginPut(
            fragmentId: id,
            size: f.bytes.length,
            accountId: stranger,
          ),
          _failsWith(pb.ErrorCode.ERROR_CODE_UNAVAILABLE),
        );
        await first.add(f.bytes);
        await first.commit();
        await expectLater(
          () => put(s, f.bytes, owner: stranger),
          _failsWith(pb.ErrorCode.ERROR_CODE_ALREADY_EXISTS),
        );
        expect(s.record(id)!.accountId, account, reason: 'владелец прежний');
      },
    );

    test('удаление и HasFragments только про свои фрагменты', () async {
      final s = storage();
      final mine = testFragment(crypto, blobLength: 1000);
      final theirs = testFragment(crypto, seed: 2, blobLength: 1000);
      await put(s, mine.bytes);
      await put(s, theirs.bytes, owner: stranger);
      final ids = [
        fragmentIdOf(crypto, mine),
        fragmentIdOf(crypto, theirs),
        crypto.randomBytes(32),
      ];
      expect(s.has(account, ids), [true, false, false]);
      expect(s.has(stranger, ids), [false, true, false]);

      expect(s.delete(ids[0]), isTrue);
      expect(s.delete(ids[0]), isFalse);
      expect(s.has(account, ids), [false, false, false]);
      expect(s.fragmentCount, 1);
      expect(s.usedBytes, theirs.bytes.length);
      expect(
        () => s.openRead(ids[0]),
        _failsWith(pb.ErrorCode.ERROR_CODE_NOT_FOUND),
      );
      expect(s.files.fileOf(ids[0]).existsSync(), isFalse);
    });

    group('убийство процесса посреди записи', () {
      final script = File('test/crash_writer.dart').absolute.path;

      /// Запускает запись до точки [point], убивает процесс SIGKILL.
      Future<List<String>> runAndKill(
        String point, {
        int seed = 7,
        Duration? after,
      }) async {
        final process = await Process.start(Platform.resolvedExecutable, [
          'run',
          script,
          dir.path,
          point,
          '$seed',
        ]);
        final lines = <String>[];
        final reached = Completer<void>();
        final out = process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
              lines.add(line);
              if (line == point && !reached.isCompleted) reached.complete();
            });
        final err = StringBuffer();
        final errDone = process.stderr
            .transform(utf8.decoder)
            .forEach(err.write);
        if (after != null) {
          // Ждём первого сохранённого фрагмента, затем ещё немного.
          final deadline = DateTime.now().add(const Duration(seconds: 60));
          while (!lines.any((l) => l.startsWith('stored '))) {
            if (DateTime.now().isAfter(deadline)) {
              fail('процесс не пишет: $err');
            }
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          await Future<void>.delayed(after);
        } else {
          await reached.future.timeout(
            const Duration(seconds: 60),
            onTimeout: () => fail('процесс не дошёл до $point: $err'),
          );
        }
        process.kill(ProcessSignal.sigkill);
        await process.exitCode;
        await out.cancel();
        await errDone;
        return lines;
      }

      late final f = testFragment(crypto, seed: 7, blobLength: 1 << 20);

      for (final point in ['writing', 'received', 'journaled']) {
        test('$point: фрагмента нет, временные файлы удалены', () async {
          await runAndKill(point);
          final id = fragmentIdOf(crypto, f);
          final tmp = Directory('${dir.path}/fragments/tmp');
          expect(tmp.listSync(), isNotEmpty, reason: 'временный файл остался');
          final s = storage();
          expect(s.record(id), isNull);
          expect(s.files.fileOf(id).existsSync(), isFalse);
          expect(filesUnder(s.files.root), isEmpty);
          // Тот же фрагмент принимается заново.
          await put(s, f.bytes);
          expect(s.record(id)!.state, FragmentState.stored);
        });
      }

      test('installed: запись доводится до конца при открытии', () async {
        await runAndKill('installed');
        final id = fragmentIdOf(crypto, f);
        final s = storage();
        expect(s.record(id)!.state, FragmentState.stored);
        Fragment.parse(s.files.fileOf(id).readAsBytesSync())
            .verify(crypto, expectedFragmentId: id);
        expect(s.usedBytes, f.bytes.length);
      });

      test('в случайный момент: под рабочими именами только целые '
          'фрагменты из индекса', () async {
        for (final delay in [0, 37, 151]) {
          await runAndKill(
            'loop',
            seed: 100 + delay * 10,
            after: Duration(milliseconds: delay),
          );
          final s = storage();
          final names = filesUnder(s.files.root);
          expect(names.where((n) => n.startsWith('tmp/')), isEmpty);
          expect(names, hasLength(s.fragmentCount));
          for (final name in names) {
            final hex = name.split('/').last.replaceAll('.frag', '');
            final id = hexToBytes(hex);
            expect(s.record(id)?.state, FragmentState.stored);
            Fragment.parse(s.files.fileOf(id).readAsBytesSync())
                .verify(crypto, expectedFragmentId: id);
          }
          await reopen(s);
        }
      });
    });
  });

  group('индекс и талоны (3.2.2)', () {
    test('индекс переживает перезапуск', () async {
      var s = storage();
      final f = testFragment(crypto, blobLength: 5000);
      await put(s, f.bytes);
      await reopen(s);
      s = storage();
      final r = s.record(fragmentIdOf(crypto, f))!;
      expect(r.accountId, account);
      expect(r.bodyRoot, f.header.bodyRoot);
      expect(s.usedBytes, f.bytes.length);
      if (!Platform.isWindows) {
        final mode = File('${dir.path}/fragments.db').statSync().modeString();
        expect(mode, 'rw-------');
      }
    });

    test('повторный талон отклоняется и после перезапуска', () async {
      var now = DateTime.utc(2026, 10, 25, 12);
      var s = storage(clock: () => now);
      final ticket = crypto.randomBytes(16);
      final expires = now.add(const Duration(minutes: 30));
      expect(s.useTicket(ticket, expires), isTrue);
      expect(s.useTicket(ticket, expires), isFalse);
      await reopen(s);

      s = storage(clock: () => now);
      expect(
        s.useTicket(ticket, expires),
        isFalse,
        reason: 'после перезапуска',
      );
      expect(s.index.usedTicketCount, 1);

      // Пока талон может пройти проверку срока (допуск 5 минут), он помнится.
      now = expires.add(const Duration(minutes: 4));
      expect(s.useTicket(crypto.randomBytes(16), now), isTrue);
      expect(s.index.usedTicketCount, 2);
      expect(s.useTicket(ticket, expires), isFalse);
      // Потом забывается: его отклонит проверка срока.
      now = expires.add(const Duration(minutes: 6));
      expect(s.useTicket(crypto.randomBytes(16), now), isTrue);
      expect(s.index.usedTicketCount, 2);
    });
  });

  group('квота и место (3.2.3)', () {
    test('сверх квоты — QUOTA_EXCEEDED', () async {
      final f1 = testFragment(crypto, blobLength: 4000);
      final f2 = testFragment(crypto, seed: 2, blobLength: 4000);
      final s = storage(quota: f1.bytes.length + f2.bytes.length - 1);
      await put(s, f1.bytes);
      expect(s.freeBytes, f2.bytes.length - 1);
      await expectLater(
        () => put(s, f2.bytes),
        _failsWith(pb.ErrorCode.ERROR_CODE_QUOTA_EXCEEDED),
      );
      s.delete(fragmentIdOf(crypto, f1));
      await put(s, f2.bytes);
    });

    test('принимаемые фрагменты занимают место заранее', () async {
      final f1 = testFragment(crypto, blobLength: 4000);
      final f2 = testFragment(crypto, seed: 2, blobLength: 4000);
      final s = storage(quota: f1.bytes.length + 100);
      final incoming = await s.beginPut(
        fragmentId: fragmentIdOf(crypto, f1),
        size: f1.bytes.length,
        accountId: account,
      );
      expect(s.freeBytes, 100);
      await expectLater(
        () => put(s, f2.bytes),
        _failsWith(pb.ErrorCode.ERROR_CODE_QUOTA_EXCEEDED),
      );
      await incoming.abort();
      expect(s.freeBytes, f1.bytes.length + 100);
    });

    test('запас свободного места на диске', () async {
      final f = testFragment(crypto, blobLength: 4000);
      var disk = 10000 + f.bytes.length;
      final s = storage(reserve: 10000, disk: (_) => disk);
      expect(s.freeBytes, f.bytes.length);
      disk--;
      expect(s.freeBytes, f.bytes.length - 1);
      await expectLater(
        () => put(s, f.bytes),
        _failsWith(pb.ErrorCode.ERROR_CODE_QUOTA_EXCEEDED),
      );
      disk = 9000;
      expect(s.freeBytes, 0, reason: 'не отрицательное');

      // Уже записанная часть принимаемого фрагмента есть на диске: она
      // вычитается из свободного места один раз.
      disk = 1 << 30;
      final incoming = await s.beginPut(
        fragmentId: fragmentIdOf(crypto, f),
        size: f.bytes.length,
        accountId: account,
      );
      await incoming.add(f.bytes.sublist(0, 1000));
      disk -= 1000;
      expect(s.freeBytes, (1 << 30) - 10000 - f.bytes.length);
      await incoming.abort();
    });

    test('настоящее свободное место на диске определяется', () {
      final s = storage();
      if (!(Platform.isLinux || Platform.isMacOS || Platform.isWindows)) return;
      final available = diskAvailableBytes(dir.path);
      expect(available, greaterThan(0));
      expect(s.diskAvailable, isNull, reason: 'в тестах подменено');
    });
  });
}
