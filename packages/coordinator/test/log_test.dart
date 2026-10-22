// Журнал координатора: JSON Lines без ключей, тел запросов и IP-адресов
// (задача 2.1.4).

import 'dart:convert';
import 'dart:io';

import 'package:coordinator/coordinator.dart';
import 'package:core/core.dart';
import 'package:logging/logging.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';

import 'support/harness.dart';

final class _FailingService extends CoordinatorService {
  const new();

  @override
  Future<pb.GetObjectResponse> getObject(
    CallContext context,
    pb.GetObjectRequest request,
  ) => throw StateError('объект ${utf8.decode(request.objectId)}');
}

void main() {
  test(
    'записи — строки JSON, без ключей, тел, IP и текста исключений',
    () async {
      final sink = StringBuffer();
      final writer = JsonLogWriter(sink)..attach(Level.ALL);
      addTearDown(writer.detach);

      final h = await Harness.create(
        service: const _FailingService(),
        trustForwardedFor: true,
      );
      final key = await h.newKey(kind: KeyKind.device);
      const marker = 'SECRET-OBJECT-MARKER';
      final body = pb.GetObjectRequest(objectId: utf8.encode(marker))
          .writeToBuffer();
      const ip = '203.0.113.77';
      final headers = {'x-forwarded-for': ip};

      final auth = await RequestAuth.sign(
        h.crypto,
        key,
        path: '/api/v1/GetObject',
        body: body,
        timeMs: h.clock.now.millisecondsSinceEpoch,
      );
      // Успешная проверка подписи и сбой обработчика, повтор, неверная
      // подпись, неизвестный метод, плохое тело.
      for (final header in [auth.toHeader(), auth.toHeader(), 'garbage']) {
        await h.post('GetObject', body, authHeader: header, headers: headers);
      }
      await h.post('Nothing', body, headers: headers);
      await h.post('GetKeyBundle', [0xFF, 0xFF], headers: headers);
      await Future<void>.delayed(Duration.zero);

      final lines = const LineSplitter().convert('$sink');
      expect(lines, hasLength(greaterThanOrEqualTo(5)));
      final records = [
        for (final l in lines) jsonDecode(l) as Map<String, Object?>,
      ];
      for (final r in records) {
        expect(r.keys, containsAll(['ts', 'level', 'logger', 'event']));
      }
      final requests = records.where((r) => r['event'] == 'request').toList();
      expect(requests.map((r) => r['code']), [
        'INTERNAL',
        'UNAUTHENTICATED',
        'UNAUTHENTICATED',
        'NOT_FOUND',
        'BAD_REQUEST',
      ]);
      expect(requests.first['method'], 'GetObject');
      expect(requests.first['in'], body.length);
      expect(
        records.where((r) => r['event'] == 'unhandled').single['error'],
        'StateError',
      );

      final text = '$sink';
      for (final secret in [
        marker,
        bytesToHex(utf8.encode(marker)),
        base64.encode(body),
        bytesToHex(body),
        bytesToHex(key.publicKey),
        base64.encode(key.publicKey),
        bytesToHex(auth.signature),
        ip,
      ]) {
        expect(text, isNot(contains(secret)), reason: secret);
      }
    },
  );

  test('ошибка пишется типом и стеком', () {
    final sink = StringBuffer();
    JsonLogWriter(sink).write(
      LogRecord(
        Level.SEVERE,
        'x',
        'test',
        const FileSystemException('путь /home/user/секрет'),
        StackTrace.current,
      ),
    );
    final record = jsonDecode('$sink') as Map<String, Object?>;
    expect(record['error'], 'FileSystemException');
    expect('$sink', isNot(contains('секрет')));
    expect(record['stack'], isA<String>());
  });

  test('поля LogEvent выводятся ключами', () {
    final sink = StringBuffer();
    JsonLogWriter(sink).write(
      LogRecord(
        Level.INFO,
        'request',
        'coordinator.api',
        null,
        null,
        null,
        const LogEvent('request', {'status': 200, 'ms': 3}),
      ),
    );
    final record = jsonDecode('$sink') as Map<String, Object?>;
    expect(record, containsPair('event', 'request'));
    expect(record, containsPair('status', 200));
    expect(record, containsPair('level', 'info'));
  });
}
