import 'dart:io';

import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/fragment_store_contract.dart';

void main() {
  late CryptoProvider crypto;
  late Directory dir;
  setUpAll(() async => crypto = await SodiumCryptoProvider.load());
  setUp(() => dir = Directory.systemTemp.createTempSync('fs-frag-'));
  tearDown(() => dir.deleteSync(recursive: true));

  LocalFolderStore open({FaultPlan faults = FaultPlan.none, int nodes = 4}) =>
      LocalFolderStore(dir, crypto, nodeCount: nodes, faults: faults);

  group('LocalFolderStore', () {
    fragmentStoreContract(() async => open(), () => crypto);

    test('папки узлов и файлы фрагментов', () async {
      final store = open(nodes: 3);
      expect(store.nodes, ['node-00', 'node-01', 'node-02']);
      final fragment = sampleFragments(crypto).first;
      final id = await store.put('node-01', fragment.toBytes());
      final files = Directory('${dir.path}/node-01')
          .listSync(recursive: true)
          .whereType<File>()
          .toList();
      expect(files.single.path, endsWith('${bytesToHex(id)}.frag'));
      expect(() => store.has('node-99', [id]), throwsArgumentError);
    });

    test('недоступный узел — StorageException unavailable', () async {
      final store = open(
        faults: const FaultPlan(unavailableNodes: {'node-02'}),
      );
      final fragment = sampleFragments(crypto).first.toBytes();
      await expectLater(
        store.put('node-02', fragment),
        throwsA(
          isA<StorageException>().having(
            (e) => e.problem,
            'problem',
            StorageProblem.unavailable,
          ),
        ),
      );
      await store.put('node-01', fragment);
    });

    test(
      'сбой записи на середине: фрагмента нет, временный файл убран',
      () async {
        final fragment = sampleFragments(crypto).first;
        final store = open(faults: const FaultPlan(failWriteRate: 1));
        await expectLater(
          store.put('node-00', fragment.toBytes()),
          throwsA(isA<StorageException>()),
        );
        final id = fragment.header.fragmentId(crypto);
        expect(await store.has('node-00', [id]), [false]);
        final leftovers = Directory('${dir.path}/node-00')
            .listSync(recursive: true)
            .whereType<File>();
        expect(leftovers, hasLength(1), reason: 'недописанный временный файл');
        // Повторное открытие убирает его.
        open();
        expect(
          Directory('${dir.path}/node-00')
              .listSync(recursive: true)
              .whereType<File>(),
          isEmpty,
        );
      },
    );

    test('порча при чтении распознаётся проверкой фрагмента', () async {
      final fragment = sampleFragments(crypto).first;
      await open().put('node-00', fragment.toBytes());
      final store = open(faults: const FaultPlan(corruptReadRate: 1));
      final id = fragment.header.fragmentId(crypto);
      final bytes = await store.get('node-00', id);
      expect(bytes, isNot(fragment.toBytes()));
      expect(
        () => Fragment.parse(bytes).verify(crypto, expectedFragmentId: id),
        throwsA(isA<CoreException>()),
      );
    });

    test('порча на диске', () async {
      final fragment = sampleFragments(crypto).first;
      final store = open();
      final id = await store.put('node-00', fragment.toBytes());
      store.corruptStored('node-00', id);
      final bytes = await store.get('node-00', id);
      expect(
        () => Fragment.parse(bytes).verify(crypto),
        throwsA(isA<IntegrityException>()),
      );
    });

    test('сбои воспроизводимы по seed и не зависят от порядка', () async {
      final fragments = [
        for (var s = 1; s <= 10; s++) ...sampleFragments(crypto, seed: s),
      ];
      Future<Set<String>> failed(int seed, {bool reversed = false}) async {
        final store = LocalFolderStore(
          Directory('${dir.path}/run-$seed-$reversed'),
          crypto,
          nodeCount: 4,
          faults: FaultPlan(seed: seed, failWriteRate: 0.3),
        );
        final out = <String>{};
        final order = reversed ? fragments.reversed : fragments;
        for (final f in order) {
          try {
            await store.put(
              'node-${f.header.index.toString().padLeft(2, '0')}',
              f.toBytes(),
            );
          } on StorageException {
            out.add(bytesToHex(f.header.fragmentId(crypto)));
          }
        }
        return out;
      }

      final a = await failed(42);
      expect(await failed(42, reversed: true), a);
      expect(a.length, inInclusiveRange(4, 22), reason: 'около 30% из 40');
      expect(await failed(43), isNot(a));
    });
  });

  test(
    'размещение: ни один сегмент не кладёт два фрагмента на один узел',
    () async {
      final store = open(nodes: 25);
      for (var s = 1; s <= 8; s++) {
        final fragments = sampleFragments(
          crypto,
          seed: s,
          k: 10,
          n: 20,
          length: 20000,
        );
        final placed = placeFragments(
          fragments.first.header.segmentId,
          store.nodes,
          20,
        );
        for (var i = 0; i < 20; i++) {
          await store.put(placed[i], fragments[i].toBytes());
        }
        for (final node in store.nodes) {
          final present = await store.has(node, [
            for (final f in fragments) f.header.fragmentId(crypto),
          ]);
          expect(
            present.where((p) => p).length,
            lessThanOrEqualTo(1),
            reason: '$node, сегмент $s',
          );
        }
      }
    },
  );
}
