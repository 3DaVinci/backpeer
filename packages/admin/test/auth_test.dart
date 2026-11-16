import 'dart:math';

import 'package:admin/src/auth.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  late PasswordHasher hasher;

  setUpAll(() {
    hasher = PasswordHasher(
      DartCryptoProvider(),
      params: const Argon2Params(memoryKiB: 8 * 1024, iterations: 1),
    );
  });

  test('хэш Argon2id проверяется, чужой и испорченный — нет', () async {
    final hash = await hasher.hashPassword('operator-password-123');
    expect(hash, startsWith(r'argon2id$v=19$m=8192,t=1,p=1$'));
    expect(await hasher.verify('operator-password-123', hash), isTrue);
    expect(await hasher.verify('operator-password-124', hash), isFalse);
    expect(await hasher.verify('operator-password-123', 'plain'), isFalse);
    expect(
      await hasher.verify(
        'operator-password-123',
        hash.replaceFirst('m=8192', 'm=2'),
      ),
      isFalse,
    );
  });

  test('короткий пароль не принимается', () async {
    await expectLater(
      hasher.hashPassword('short'),
      throwsA(isA<PasswordPolicyException>()),
    );
  });

  test('сессия истекает по часам', () {
    var now = DateTime.utc(2026, 11, 16, 12);
    final store = SessionStore(
      lifetime: const Duration(minutes: 30),
      clock: () => now,
      random: Random(1),
    );
    final session = store.create('operator');
    expect(store.lookup(session.token), isNotNull);
    now = now.add(const Duration(minutes: 31));
    expect(store.lookup(session.token), isNull);
    expect(store.activeCount, 0);
  });

  test('вход, неверный пароль и блокировка имени', () async {
    final sessions = SessionStore(lifetime: const Duration(hours: 1));
    final auth = AdminAuthenticator(
      users: {'operator': await hasher.hashPassword('operator-password-123')},
      hasher: hasher,
      sessions: sessions,
      maxFailedAttempts: 3,
      lockDuration: const Duration(minutes: 10),
    );
    final ok = await auth.login('operator', 'operator-password-123');
    expect(ok.ok, isTrue);
    expect(ok.session!.user, 'operator');
    expect(sessions.lookup(ok.session!.token), isNotNull);

    expect((await auth.login('operator', 'wrong')).ok, isFalse);
    expect((await auth.login('OPERATOR ', 'wrong')).ok, isFalse);
    expect((await auth.login('operator', 'wrong')).ok, isFalse);
    final locked = await auth.login('operator', 'operator-password-123');
    expect(locked.ok, isFalse);
    expect(locked.lockedUntil, isNotNull);

    final unknown = await auth.login('nobody', 'operator-password-123');
    expect(unknown.ok, isFalse);
  });

  test('выход удаляет сессию', () {
    final sessions = SessionStore(lifetime: const Duration(hours: 1));
    final session = sessions.create('operator');
    sessions.destroy(session.token);
    expect(sessions.lookup(session.token), isNull);
  });
}
