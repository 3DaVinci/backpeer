import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:core/core.dart' show redactCrashText;

/// Отчёт о сбое приложения в том виде, в каком его приняла панель
/// (`docs/spec/crash-reports.md`). Полей личности нет: ни адреса клиента,
/// ни имени учётной записи, ни путей.
final class CrashReport {
  const new({
    required this.id,
    required this.at,
    required this.receivedAt,
    required this.version,
    required this.os,
    required this.error,
    required this.stack,
    required this.source,
  });

  final String id;
  final DateTime at;
  final DateTime receivedAt;
  final String version;
  final String os;
  final String error;
  final String stack;

  /// Откуда пришёл отчёт: `app`, `node`, `agent`, `unknown`.
  final String source;

  Map<String, Object?> toJson() => {
    'id': id,
    'at': at.toUtc().toIso8601String(),
    'receivedAt': receivedAt.toUtc().toIso8601String(),
    'version': version,
    'os': os,
    'error': error,
    'stack': stack,
    'source': source,
  };

  static CrashReport? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final at = DateTime.tryParse('${value['at'] ?? ''}');
    final receivedAt = DateTime.tryParse('${value['receivedAt'] ?? ''}');
    final version = value['version'];
    final os = value['os'];
    final error = value['error'];
    final stack = value['stack'];
    if (id is! String ||
        id.isEmpty ||
        at == null ||
        receivedAt == null ||
        version is! String ||
        os is! String ||
        error is! String ||
        stack is! String) {
      return null;
    }
    return CrashReport(
      id: id,
      at: at.toUtc(),
      receivedAt: receivedAt.toUtc(),
      version: version,
      os: os,
      error: error,
      stack: stack,
      source: value['source'] is String ? value['source']! as String : 'app',
    );
  }
}

/// Страница отчётов и общее число подходящих записей.
final class CrashReportPage {
  const new({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  final List<CrashReport> items;
  final int total;
  final int limit;
  final int offset;

  Map<String, Object?> toJson() => {
    'items': [for (final report in items) report.toJson()],
    'total': total,
    'limit': limit,
    'offset': offset,
  };
}

/// Сводка по отчётам для панели: сколько, какие версии, ОС и повторы.
final class CrashReportSummary {
  const new({
    required this.total,
    required this.last24h,
    required this.last7d,
    required this.byDay,
    required this.byVersion,
    required this.byOs,
    required this.top,
  });

  final int total;
  final int last24h;
  final int last7d;
  final List<Map<String, Object?>> byDay;
  final List<Map<String, Object?>> byVersion;
  final List<Map<String, Object?>> byOs;
  final List<Map<String, Object?>> top;

  Map<String, Object?> toJson() => {
    'total': total,
    'last24h': last24h,
    'last7d': last7d,
    'byDay': byDay,
    'byVersion': byVersion,
    'byOs': byOs,
    'top': top,
  };
}

/// Файловое хранилище отчётов: `<папка>/ГГГГ-ММ-ДД.jsonl`.
///
/// Записи только добавляются; срок хранения удаляет старые файлы. В память
/// загружается не больше `maxEntries` последних отчётов — этого хватает
/// панели, а объём памяти не зависит от возраста данных.
final class CrashReportStore {
  new _({
    required this.directory,
    required this.retentionDays,
    required this.maxEntries,
    required this.maxMemoryBytes,
    required this.clock,
    required this.random,
  });

  final Directory directory;
  final int retentionDays;
  final int maxEntries;
  final int maxMemoryBytes;
  final DateTime Function() clock;
  final Random random;

  final List<CrashReport> _reports = [];
  int _memoryBytes = 0;
  Future<void> _queue = Future<void>.value();

  static final _file = RegExp(r'^\d{4}-\d{2}-\d{2}\.jsonl$');

  static Future<CrashReportStore> open({
    required String path,
    required int retentionDays,
    required int maxEntries,
    int maxMemoryBytes = 64 << 20,
    DateTime Function()? clock,
    Random? random,
  }) async {
    final directory = Directory(path);
    await directory.create(recursive: true);
    if (!Platform.isWindows) {
      // Отчёты не содержат ключей, но стек и сообщения — внутреннее
      // дело продукта: папка только для владельца службы.
      try {
        await Process.run('chmod', ['700', directory.path]);
      } on ProcessException {
        // Не получилось — права задаёт администратор (docs/ops/admin.md).
      }
    }
    final store = CrashReportStore._(
      directory: directory,
      retentionDays: retentionDays,
      maxEntries: maxEntries,
      maxMemoryBytes: maxMemoryBytes,
      clock: clock ?? DateTime.now,
      random: random ?? Random.secure(),
    );
    await store._load();
    await store._prune();
    return store;
  }

  List<CrashReport> get reports => List.unmodifiable(_reports);

  Future<void> _load() async {
    _reports.clear();
    _memoryBytes = 0;
    final files = await directory
        .list()
        .where((e) => e is File && _file.hasMatch(_base(e.path)))
        .cast<File>()
        .toList();
    files.sort((a, b) => _base(b.path).compareTo(_base(a.path)));
    for (final file in files) {
      if (_reports.length >= maxEntries) break;
      final List<String> lines;
      try {
        lines = await file.readAsLines();
      } on FileSystemException {
        continue;
      }
      for (final line in lines.reversed) {
        if (_reports.length >= maxEntries) break;
        if (line.trim().isEmpty) continue;
        try {
          final report = CrashReport.fromJson(jsonDecode(line));
          if (report != null && _fits(report)) {
            _reports.add(report);
            _memoryBytes += _size(report);
          }
        } on FormatException {
          // Испорченная строка не мешает остальным.
        }
      }
    }
    _reports.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
  }

  /// Принимает уже проверенный JSON от приложения. Очистка повторяется на
  /// сервере: старый клиент мог не знать новых правил.
  Future<CrashReport> add(Map<String, Object?> raw, {String? source}) {
    final completer = Completer<CrashReport>();
    _queue = _queue.then((_) async {
      try {
        final report = _validate(raw, source: source);
        final file = File('${directory.path}/${_day(report.receivedAt)}.jsonl');
        await file.writeAsString(
          '${jsonEncode(report.toJson())}\n',
          mode: FileMode.append,
          flush: true,
        );
        _reports.insert(0, report);
        _memoryBytes += _size(report);
        while (_reports.length > maxEntries ||
            (_memoryBytes > maxMemoryBytes && _reports.length > 1)) {
          final removed = _reports.removeLast();
          _memoryBytes -= _size(removed);
        }
        completer.complete(report);
      } on Object catch (e, stack) {
        completer.completeError(e, stack);
      }
    });
    return completer.future;
  }

  CrashReport _validate(Map<String, Object?> raw, {String? source}) {
    final now = clock().toUtc();
    String text(String key) {
      final value = raw[key];
      return value is String ? value : '';
    }

    final version = text('version').trim();
    final os = text('os').trim();
    final error = redactCrashText(text('error')).trim();
    final stack = redactCrashText(text('stack')).trim();
    final atText = text('at').trim();
    final at = DateTime.tryParse(atText)?.toUtc();
    if (version.isEmpty || version.length > 64) {
      throw const CrashReportException('version: пусто или длиннее 64');
    }
    if (os.length > 200) {
      throw const CrashReportException('os: длиннее 200');
    }
    if (error.isEmpty || error.length > 8192) {
      throw const CrashReportException('error: пусто или длиннее 8192');
    }
    if (stack.length > 65536) {
      throw const CrashReportException('stack: длиннее 65536');
    }
    if (at == null) {
      throw const CrashReportException('at: нужно время ISO 8601');
    }
    if (at.isAfter(now.add(const Duration(minutes: 10)))) {
      throw const CrashReportException('at: время в будущем');
    }
    final name = _source(source);
    final id = '${_stamp(now)}-${_hex(8)}';
    return CrashReport(
      id: id,
      at: at,
      receivedAt: now,
      version: version,
      os: os,
      error: error,
      stack: stack,
      source: name,
    );
  }

  static String _source(String? value) {
    final source = (value ?? 'app').toLowerCase();
    if (!RegExp(r'^[a-z][a-z0-9._-]{0,31}$').hasMatch(source)) return 'app';
    return source;
  }

  CrashReportPage list({
    String query = '',
    String? version,
    String? os,
    int days = 0,
    int limit = 50,
    int offset = 0,
  }) {
    final q = query.trim().toLowerCase();
    final since = days > 0
        ? clock().toUtc().subtract(Duration(days: days))
        : null;
    final filtered = _reports.where((report) {
      if (version != null && version.isNotEmpty && report.version != version) {
        return false;
      }
      if (os != null && os.isNotEmpty && report.os != os) return false;
      if (since != null && report.receivedAt.isBefore(since)) return false;
      if (q.isEmpty) return true;
      return report.error.toLowerCase().contains(q) ||
          report.stack.toLowerCase().contains(q) ||
          report.version.toLowerCase().contains(q) ||
          report.os.toLowerCase().contains(q);
    }).toList();
    final start = offset.clamp(0, filtered.length);
    final end = (start + limit).clamp(start, filtered.length);
    return CrashReportPage(
      items: filtered.sublist(start, end),
      total: filtered.length,
      limit: limit,
      offset: start,
    );
  }

  CrashReport? get(String id) {
    for (final report in _reports) {
      if (report.id == id) return report;
    }
    return null;
  }

  CrashReportSummary summary() {
    final now = clock().toUtc();
    final last24h = _reports
        .where(
          (r) => r.receivedAt.isAfter(now.subtract(const Duration(hours: 24))),
        )
        .length;
    final last7d = _reports
        .where(
          (r) => r.receivedAt.isAfter(now.subtract(const Duration(days: 7))),
        )
        .length;
    final byDay = <String, int>{};
    for (var i = 13; i >= 0; i--) {
      byDay[_day(now.subtract(Duration(days: i)))] = 0;
    }
    final versions = <String, int>{};
    final systems = <String, int>{};
    final top = <String, int>{};
    for (final report in _reports) {
      final day = _day(report.receivedAt);
      if (byDay.containsKey(day)) byDay[day] = byDay[day]! + 1;
      versions[report.version] = (versions[report.version] ?? 0) + 1;
      systems[report.os] = (systems[report.os] ?? 0) + 1;
      final signature = _signature(report.error);
      top[signature] = (top[signature] ?? 0) + 1;
    }
    return CrashReportSummary(
      total: _reports.length,
      last24h: last24h,
      last7d: last7d,
      byDay: [
        for (final entry in byDay.entries)
          {'day': entry.key, 'count': entry.value},
      ],
      byVersion: _top(versions),
      byOs: _top(systems),
      top: _top(top),
    );
  }

  bool _fits(CrashReport report) =>
      _reports.length < maxEntries &&
      _memoryBytes + _size(report) <= maxMemoryBytes;

  static int _size(CrashReport report) =>
      report.error.length + report.stack.length + 256;

  static List<Map<String, Object?>> _top(Map<String, int> values) {
    final entries = values.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final entry in entries.take(12))
        {'name': entry.key, 'count': entry.value},
    ];
  }

  /// Подпись ошибки — первая строка с заменой чисел: повторяющиеся сбои
  /// с разными идентификаторами собираются вместе.
  static String _signature(String error) {
    final first = error.split('\n').first.trim();
    final normalized = first.replaceAll(RegExp(r'\d+'), '#');
    return normalized.length <= 160
        ? normalized
        : '${normalized.substring(0, 157)}…';
  }

  Future<void> _prune() async {
    final cutoff = clock().toUtc().subtract(Duration(days: retentionDays));
    final cutoffDay = _day(cutoff);
    await for (final entry in directory.list()) {
      if (entry is! File) continue;
      final name = _base(entry.path);
      if (!_file.hasMatch(name)) continue;
      if (name.substring(0, 10).compareTo(cutoffDay) < 0) {
        try {
          await entry.delete();
        } on FileSystemException {
          // Не удалилось — попробуем в следующий раз.
        }
      }
    }
  }

  /// Периодическая уборка: вызывается сервером раз в сутки.
  Future<void> prune() async {
    await _prune();
    await _load();
  }

  String _hex(int bytes) => [
    for (var i = 0; i < bytes; i++)
      random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();

  static String _stamp(DateTime time) =>
      '${_day(time).replaceAll('-', '')}T'
      '${time.hour.toString().padLeft(2, '0')}'
      '${time.minute.toString().padLeft(2, '0')}'
      '${time.second.toString().padLeft(2, '0')}';

  static String _day(DateTime time) {
    final utc = time.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}-'
        '${utc.day.toString().padLeft(2, '0')}';
  }

  static String _base(String path) => path.split(Platform.pathSeparator).last;
}

/// Отчёт не подходит по формату.
final class CrashReportException implements Exception {
  const new(this.message);

  final String message;

  @override
  String toString() => 'CrashReportException: $message';
}
