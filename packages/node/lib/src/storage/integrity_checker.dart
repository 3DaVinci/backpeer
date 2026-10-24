import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:logging/logging.dart';
import 'package:node/src/daemon/log.dart';
import 'package:node/src/storage/fragment_files.dart';
import 'package:node/src/storage/fragment_index.dart';
import 'package:node/src/storage/fragment_storage.dart';

/// Итог проверки одного фрагмента.
final class FragmentCheck {
  const new(this.fragmentId, this.size, this.damage);

  final Uint8List fragmentId;
  final int size;

  /// Почему фрагмент повреждён; `null` — цел.
  final String? damage;

  bool get ok => damage == null;
}

/// Фоновая проверка целостности (задача 3.2.4): фрагменты по очереди,
/// начиная с дольше всех не проверявшегося, читаются с диска и
/// сверяются — заголовок, `fragment_id = H(заголовок)`, длина, корень
/// дерева тела (data-format.md, раздел 5). Каждый фрагмент проверяется не
/// реже чем раз в [interval]; скорость чтения — не больше
/// [bytesPerSecond], чтобы проверка не мешала передачам и владельцу
/// компьютера.
///
/// Повреждённый или пропавший фрагмент получает состояние
/// [FragmentState.damaged], больше не выдаётся и попадает в отчёт
/// координатору ([onDamaged], `ReportDamagedFragments`). Обработка —
/// ремонт в этапе 4.
///
/// Если пропала вся папка фрагментов (например, не подключён внешний
/// диск NAS), фрагменты не помечаются: проверка ждёт, пока папка
/// вернётся.
final class IntegrityChecker {
  new({
    required this.storage,
    required this._crypto,
    this.interval = const Duration(days: 30),
    this.bytesPerSecond = 10000000,
    this.idlePause = const Duration(hours: 1),
    this.onDamaged,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final FragmentStorage storage;
  final CryptoProvider _crypto;

  /// Как часто проверять каждый фрагмент.
  final Duration interval;

  /// Предел скорости чтения; 0 — без предела.
  final int bytesPerSecond;

  /// Пауза, когда проверять нечего.
  final Duration idlePause;

  /// Вызывается после каждого найденного повреждения.
  void Function(FragmentCheck check)? onDamaged;
  final DateTime Function() _clock;

  static final _log = Logger('integrity');

  int checked = 0;
  int damaged = 0;
  DateTime? lastCheckAt;

  bool _stopped = false;
  Completer<void>? _wake;
  Future<void>? _loop;

  Map<String, Object?> toJson() => {
    'fragmentsChecked': checked,
    'fragmentsDamaged': damaged,
    'lastCheckAt': lastCheckAt?.toUtc().toIso8601String(),
  };

  void start() => _loop ??= _run();

  /// Останавливает проверку; текущий фрагмент дочитывается.
  Future<void> stop() async {
    _stopped = true;
    if (_wake case final w? when !w.isCompleted) w.complete();
    await _loop;
  }

  Future<void> _run() async {
    while (!_stopped) {
      FragmentCheck? result;
      final watch = Stopwatch()..start();
      try {
        result = await checkNext();
      } on Object catch (e, st) {
        _log.severe(LogEvent('check_failed', {'reason': '$e'}), null, st);
      }
      if (_stopped) break;
      if (result == null) {
        await _sleep(idlePause);
        continue;
      }
      if (bytesPerSecond > 0) {
        final budget = Duration(
          microseconds: result.size * 1000000 ~/ bytesPerSecond,
        );
        final rest = budget - watch.elapsed;
        if (rest > Duration.zero) await _sleep(rest);
      }
    }
  }

  Future<void> _sleep(Duration d) async {
    final wake = _wake = Completer<void>();
    final timer = Timer(d, () {
      if (!wake.isCompleted) wake.complete();
    });
    await wake.future;
    timer.cancel();
  }

  /// Проверяет очередной фрагмент, срок проверки которого подошёл;
  /// `null` — проверять нечего (или папка фрагментов недоступна).
  Future<FragmentCheck?> checkNext() async {
    final record = storage.index.nextToCheck(_clock().subtract(interval));
    if (record == null) return null;
    return await check(record);
  }

  /// Проверяет [record] и записывает итог в индекс; `null` — папка
  /// фрагментов недоступна, итог не записан.
  Future<FragmentCheck?> check(FragmentRecord record) async {
    final id = record.fragmentId;
    String? damage;
    try {
      final verifier = FragmentVerifier(
        _crypto,
        expectedFragmentId: id,
        expectedSize: record.size,
      );
      await storage.files.fileOf(id).openRead().forEach(verifier.add);
      final header = verifier.finish();
      if (!constantTimeEquals(header.bodyRoot, record.bodyRoot)) {
        damage = 'body_root не совпадает с индексом';
      }
    } on FragmentStorageException catch (e) {
      damage = e.message;
    } on PathNotFoundException {
      if (!storage.files.root.existsSync()) {
        _log.warning(
          LogEvent('fragments_dir_missing', {'path': storage.files.root.path}),
        );
        return null;
      }
      damage = 'файл фрагмента пропал';
    } on FileSystemException catch (e) {
      damage = 'ошибка чтения: ${e.osError?.message ?? e.message}';
    }
    lastCheckAt = _clock();
    checked++;
    final result = FragmentCheck(id, record.size, damage);
    if (damage == null) {
      storage.markChecked(id);
      return result;
    }
    damaged++;
    storage.markDamaged(id, damage);
    _log.warning(
      LogEvent('fragment_damaged', {
        'fragment_id': bytesToHex(id),
        'reason': damage,
      }),
    );
    onDamaged?.call(result);
    return result;
  }
}
