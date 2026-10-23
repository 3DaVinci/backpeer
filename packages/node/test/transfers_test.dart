import 'package:node/node.dart';
import 'package:test/test.dart';

void main() {
  test('close ждёт начатые передачи и не пускает новые', () async {
    final gate = TransferGate();
    final t = gate.tryBegin()!;
    var closed = false;
    final future = gate
        .close(const Duration(seconds: 5))
        .then((ok) => closed = ok);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(closed, isFalse);
    expect(gate.tryBegin(), isNull);
    t
      ..end()
      ..end(); // повторно — без эффекта
    await future;
    expect(closed, isTrue);
    expect(gate.active, 0);
  });

  test('close по истечении срока — false; forceClose — сразу', () async {
    final gate = TransferGate()..tryBegin();
    expect(await gate.close(const Duration(milliseconds: 10)), isFalse);
    final other = TransferGate()..tryBegin();
    final f = other.close(const Duration(minutes: 1));
    other.forceClose();
    expect(await f, isFalse);
  });

  test('пауза: новые передачи не начинаются', () {
    final gate = TransferGate()..paused = true;
    expect(gate.tryBegin(), isNull);
    gate.paused = false;
    expect(gate.tryBegin(), isNotNull);
  });
}
