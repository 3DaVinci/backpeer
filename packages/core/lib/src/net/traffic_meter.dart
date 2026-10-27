import 'dart:async';
import 'dart:typed_data';

import 'package:core/src/coordinator/coordinator_client.dart';
import 'package:core/src/crypto/crypto_provider.dart';
import 'package:core/src/errors.dart';
import 'package:core/src/net/byte_connection.dart';
import 'package:fixnum/fixnum.dart';
import 'package:protocol/protocol.dart' as pb;

/// Учёт трафика с узлами по способам подключения (задача 3.8.3):
/// прямой TCP, поток поверх UDP, relay. Координатор складывает отчёты
/// клиентов и узлов (`ReportTraffic`) и считает долю relay в трафике
/// сети — показатель контрольной точки 3.10.4.
///
/// Соединение учитывается, если его обернуть [wrap]: стратегия
/// подключения (задача 3.9.1) оборачивает каждое установленное
/// соединение способом, которым оно получено.
final class TrafficMeter {
  final _bytes = <pb.ConnectionMethod, int>{};
  final _connections = <pb.ConnectionMethod, int>{};
  final _totalBytes = <pb.ConnectionMethod, int>{};

  /// [connection] со счётчиком байт в обе стороны под способом [method].
  /// [count] — учесть его и в числе соединений; стратегия подключения
  /// учитывает только победившую попытку ([countConnection]).
  ByteConnection wrap(
    ByteConnection connection,
    pb.ConnectionMethod method, {
    bool count = true,
  }) {
    if (count) countConnection(method);
    return _MeteredConnection(connection, (n) => _count(method, n));
  }

  /// Новое соединение способом [method].
  void countConnection(pb.ConnectionMethod method) =>
      _connections.update(method, (n) => n + 1, ifAbsent: () => 1);

  void _count(pb.ConnectionMethod method, int bytes) {
    _bytes.update(method, (n) => n + bytes, ifAbsent: () => bytes);
    _totalBytes.update(method, (n) => n + bytes, ifAbsent: () => bytes);
  }

  /// Прирост с прошлого вызова; счётчики обнуляются. Нечего сообщить —
  /// `null`.
  pb.ReportTrafficRequest? takeReport() {
    final methods = {..._bytes.keys, ..._connections.keys};
    if (methods.isEmpty) return null;
    final request = pb.ReportTrafficRequest(
      traffic: [
        for (final m in methods)
          pb.TrafficByMethod(
            method: m,
            bytes: Int64(_bytes[m] ?? 0),
            connections: _connections[m] ?? 0,
          ),
      ],
    );
    _bytes.clear();
    _connections.clear();
    return request;
  }

  /// Возвращает в счётчики отчёт, который не удалось отправить.
  void restore(pb.ReportTrafficRequest report) {
    for (final t in report.traffic) {
      final bytes = t.bytes.toInt();
      _bytes.update(t.method, (n) => n + bytes, ifAbsent: () => bytes);
      _connections.update(
        t.method,
        (n) => n + t.connections,
        ifAbsent: () => t.connections,
      );
    }
  }

  /// Байт с запуска по способам: `direct`, `udp`, `relay`.
  Map<String, int> toJson() => {
    for (final MapEntry(:key, :value) in _totalBytes.entries)
      methodName(key): value,
  };

  static String methodName(pb.ConnectionMethod m) =>
      m.name.replaceFirst('CONNECTION_METHOD_', '').toLowerCase();
}

final class _MeteredConnection implements ByteConnection {
  new(this._inner, this._count);

  final ByteConnection _inner;
  final void Function(int bytes) _count;

  @override
  Stream<Uint8List> get input => _inner.input.map((chunk) {
    _count(chunk.length);
    return chunk;
  });

  @override
  void add(Uint8List data) {
    _count(data.length);
    _inner.add(data);
  }

  @override
  Future<void> flush() => _inner.flush();

  @override
  Future<void> close() => _inner.close();

  @override
  void destroy() => _inner.destroy();
}

/// Отправляет координатору отчёты [meter] каждые [interval] и при
/// [stop]. Сбой — отчёт возвращается в счётчики и уйдёт со следующим.
final class TrafficReporter {
  new({
    required this.client,
    required this.meter,
    this.key,
    this.interval = const Duration(minutes: 10),
  });

  final CoordinatorClient client;
  final TrafficMeter meter;

  /// Ключ узла; `null` — ключ устройства.
  final Ed25519KeyPair? key;
  final Duration interval;
  Timer? _timer;
  Future<void>? _sending;

  void start() =>
      _timer ??= Timer.periodic(interval, (_) => unawaited(report()));

  /// Останавливает отчёты и отправляет последний.
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await report();
  }

  /// Отправляет прирост сейчас; одновременные вызовы ждут один отчёт.
  Future<void> report() => _sending ??= _send().whenComplete(() {
    _sending = null;
  });

  Future<void> _send() async {
    final request = meter.takeReport();
    if (request == null) return;
    try {
      await client.reportTraffic(request, key: key);
    } on CoordinatorException {
      meter.restore(request);
    }
  }
}
