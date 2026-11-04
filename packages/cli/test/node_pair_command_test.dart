// Команда `cli node pair` (задачи 6.1.1, 6.1.2; protocol.md, раздел 4.17):
// владелец вводит код, который показывает узел, сверяет отпечаток и
// подписывает NodeCertificate ключом учётной записи. Координатор
// подменяется локальным HTTP-сервером.

import 'dart:io';
import 'dart:typed_data';

import 'package:cli/cli.dart';
import 'package:core/core.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';

/// Консоль для тестов: отвечает на вопросы функцией, копит вывод.
final class _Console implements Console {
  new([this.answer]);

  final String? Function(String prompt, List<String> out)? answer;
  final List<String> lines = [];
  final List<String> errors = [];

  @override
  void out(String line) => lines.add(line);

  @override
  void err(String line) => errors.add(line);

  @override
  String? ask(String prompt) => answer?.call(prompt, lines);

  @override
  String? askSecret(String prompt) => answer?.call(prompt, lines);

  @override
  void progress(String line) {}
}

/// Слова фразы из вывода register.
Map<int, String> _phraseWords(List<String> out) => {
  for (final line in out)
    for (final m in RegExp(r'(\d+)\. ([a-z]+)').allMatches(line))
      int.parse(m[1]!): m[2]!,
};

/// Подставной координатор: отвечает на методы по сценарию [respond].
final class _FakeCoordinator {
  new _(this._server, this.respond) {
    _server.listen(_handle);
  }

  static Future<_FakeCoordinator> start(
    Object Function(String method, List<int> body) respond,
  ) async => _FakeCoordinator._(
    await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    respond,
  );

  final HttpServer _server;
  Object Function(String method, List<int> body) respond;
  final calls = <String>[];
  final bodies = <List<int>>[];

  String get url => 'http://127.0.0.1:${_server.port}';

  Future<void> _handle(HttpRequest request) async {
    final method = request.uri.pathSegments.last;
    final body = await request.fold<List<int>>([], (a, b) => a..addAll(b));
    calls.add(method);
    bodies.add(body);
    final reply = respond(method, body);
    request.response.headers.contentType = ContentType(
      'application',
      'x-protobuf',
    );
    if (reply case final pb.Error error) {
      request.response.statusCode = 401;
      request.response.add(error.writeToBuffer());
    } else {
      request.response.add((reply as dynamic).writeToBuffer() as List<int>);
    }
    await request.response.close();
  }

  Future<void> close() => _server.close(force: true);
}

void main() {
  late Directory dir;
  late Map<String, String> env;
  late _FakeCoordinator fake;
  late Uint8List nodeId;
  late Uint8List nodeDh;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('fs-cli-pair-');
    env = {
      'FS_HOME': '${dir.path}/home',
      'FS_PASSWORD': 'correct horse battery staple',
      'FS_ARGON2_FAST': '1',
    };
    nodeId = Uint8List(32)..[0] = 0x11;
    nodeDh = Uint8List(32)..[0] = 0x22;
    fake = await _FakeCoordinator.start((method, body) {
      switch (method) {
        case 'RegisterAccount':
          return pb.RegisterAccountResponse();
        case 'NodePairLookup':
          return pb.NodePairLookupResponse(nodeId: nodeId, nodeDh: nodeDh);
        case 'NodePairSign':
          return pb.NodePairSignResponse();
        default:
          return pb.Error(
            code: pb.ErrorCode.ERROR_CODE_NOT_FOUND,
            message: 'нет метода $method',
          );
      }
    });
  });
  tearDown(() async {
    await fake.close();
    dir.deleteSync(recursive: true);
  });

  /// Ответы на проверку трёх слов фразы при register.
  String? answerWords(String prompt, List<String> out) {
    final m = RegExp(r'Слово №(\d+)').firstMatch(prompt);
    return m == null ? null : _phraseWords(out)[int.parse(m[1]!)];
  }

  Future<void> register() async {
    final console = _Console(answerWords);
    final code = await runCli(
      ['register', '--coordinator', fake.url, '--login', 'owner'],
      console: console,
      environment: env,
    );
    expect(code, ExitCode.ok, reason: console.errors.join('\n'));
  }

  Future<(int, _Console)> pair(List<String> args) async {
    final console = _Console();
    final code = await runCli(
      ['node', 'pair', ...args],
      console: console,
      environment: env,
    );
    return (code, console);
  }

  test('полный путь: lookup → отпечаток → подписанный сертификат', () async {
    await register();
    final crypto = await SodiumCryptoProvider.load();

    final (code, console) = await pair(['ABCD1234', '--yes']);

    expect(code, ExitCode.ok, reason: console.errors.join('\n'));
    expect(console.lines.join('\n'), contains('Отпечаток узла:'));
    expect(
      console.lines.join('\n'),
      contains(nodeFingerprint(crypto, nodeId: nodeId, nodeDh: nodeDh)),
    );
    expect(console.lines.join('\n'), contains('Сертификат отправлен'));

    final lookupIndex = fake.calls.indexOf('NodePairLookup');
    final signIndex = fake.calls.indexOf('NodePairSign');
    expect(lookupIndex, greaterThanOrEqualTo(0));
    expect(signIndex, greaterThan(lookupIndex));
    expect(
      pb.NodePairLookupRequest.fromBuffer(fake.bodies[lookupIndex]).code,
      'ABCD1234',
    );
    final sign = pb.NodePairSignRequest.fromBuffer(fake.bodies[signIndex]);
    expect(sign.code, 'ABCD1234');
    // Сертификат подписан ключом учётной записи и для этих ключей узла.
    final cert = await NodeCertificates.open(
      crypto,
      sign.nodeCertificate,
      nodeId: nodeId,
    );
    expect(cert.nodeDh, nodeDh);
  });

  test('--yes не задан: отказ — привязка отменена', () async {
    await register();
    final console = _Console((prompt, out) => 'нет');
    final code = await runCli(
      ['node', 'pair', 'ABCD1234'],
      console: console,
      environment: env,
    );
    expect(code, ExitCode.cancelled);
    expect(console.errors.join('\n'), contains('Привязка отменена'));
    expect(fake.calls, isNot(contains('NodePairSign')));
  });

  test('координатор не находит код — ошибка', () async {
    await register();
    fake.respond = (method, body) => switch (method) {
      'NodePairLookup' => pb.Error(
        code: pb.ErrorCode.ERROR_CODE_NOT_FOUND,
        message: 'код неверный или просрочен',
      ),
      _ => pb.NodePairSignResponse(),
    };
    final (code, console) = await pair(['WRONG123', '--yes']);
    expect(code, ExitCode.error);
    expect(console.errors.join('\n'), contains('код неверный или просрочен'));
  });

  test('без координатора — понятная ошибка', () async {
    // init без координатора: ключи есть, но настроек координатора нет.
    final console = _Console(answerWords);
    final code = await runCli(['init'], console: console, environment: env);
    expect(code, ExitCode.ok, reason: console.errors.join('\n'));
    final (pairCode, pairConsole) = await pair(['ABCD1234', '--yes']);
    expect(pairCode, ExitCode.error);
    expect(pairConsole.errors.join('\n'), contains('Координатор не настроен'));
  });
}
