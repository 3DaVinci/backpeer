// Учётные записи, устройства, отзывы и вход по паролю (задачи 2.3, 2.4.2;
// protocol.md, раздел 4.7). Нужен FS_TEST_POSTGRES.

import 'dart:typed_data';

import 'package:coordinator/coordinator.dart';
import 'package:core/core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:postgres/postgres.dart';
import 'package:protocol/protocol.dart' as pb;
import 'package:test/test.dart';

import 'support/db_harness.dart';
import 'support/postgres.dart';

const pb.ErrorCode _badRequest = pb.ErrorCode.ERROR_CODE_BAD_REQUEST;
const pb.ErrorCode _unauthenticated = pb.ErrorCode.ERROR_CODE_UNAUTHENTICATED;
const pb.ErrorCode _alreadyExists = pb.ErrorCode.ERROR_CODE_ALREADY_EXISTS;
const pb.ErrorCode _accepted = pb.ErrorCode.ERROR_CODE_UNSPECIFIED;
const pb.ErrorCode _rateLimited = pb.ErrorCode.ERROR_CODE_RATE_LIMITED;

void main() {
  if (testPostgresUrl == null) {
    test('учётные записи', () {}, skip: skipWithoutPostgres);
    return;
  }
  late DbHarness h;
  setUp(() async => h = await DbHarness.create());
  tearDown(() => h.close());

  /// Запрос устройства: успех — [_accepted], иначе код ошибки.
  Future<pb.ErrorCode> deviceCall(Ed25519KeyPair device) async {
    try {
      await h.call(
        'ListObjects',
        pb.ListObjectsRequest(kind: pb.ObjectKind.OBJECT_KIND_SNAPSHOT),
        pb.ListObjectsResponse.fromBuffer,
        key: device,
      );
      return pb.ErrorCode.ERROR_CODE_UNSPECIFIED;
    } on RpcFailure catch (f) {
      return f.code;
    }
  }

  group('RegisterAccount', () {
    test('создаёт учётную запись с первым устройством', () async {
      final account = await h.newAccount();
      final device = await h.newKey();
      expect(await deviceCall(device), _unauthenticated);
      await h.register(account, device, login: 'Alice', password: 'пароль');
      expect(
        await deviceCall(device),
        _accepted,
        reason: 'подпись устройства принята',
      );
      final rows = await h.db.run(
        (s) => s.execute(
          Sql.named(
            'SELECT login, key_bundle IS NOT NULL FROM accounts '
            'WHERE account_id = @a:bytea',
          ),
          parameters: {'a': account.accountId},
        ),
      );
      expect(rows.single, ['alice', true]);
    });

    test('повторная регистрация и занятые имя или устройство', () async {
      final account = await h.newAccount();
      final device = await h.newKey();
      await h.register(account, device, login: 'alice');
      await expectLater(
        () => h.register(account, device, login: 'alice2'),
        failsWith(_alreadyExists),
      );
      await expectLater(
        () async => await h.register(account, await h.newKey(), login: 'other'),
        failsWith(_alreadyExists),
        reason: 'та же учётная запись',
      );
      final other = await h.newAccount();
      await expectLater(
        () async => await h.register(other, await h.newKey(), login: 'ALICE'),
        failsWith(_alreadyExists),
        reason: 'имя без учёта регистра',
      );
      await expectLater(
        () => h.register(other, device, login: 'bob'),
        failsWith(_alreadyExists),
        reason: 'устройство уже зарегистрировано',
      );
      await h.register(other, await h.newKey(), login: 'bob');
    });

    test('неверные поля и подписи', () async {
      final account = await h.newAccount();
      final other = await h.newAccount();
      final device = await h.newKey();
      Future<void> register({
        pb.Signed? cert,
        String login = 'carol',
        List<int>? bundle,
        List<int>? verifier,
      }) async => await h.call(
        'RegisterAccount',
        pb.RegisterAccountRequest(
          deviceCertificate: cert ?? await h.deviceCert(account, device),
          login: login,
          keyBundle: bundle,
          authVerifier: verifier,
        ),
        pb.RegisterAccountResponse.fromBuffer,
        key: account.accountSign,
      );

      for (final login in ['', 'ab', 'алиса', 'a b', '.x1', 'a' * 33]) {
        await expectLater(() => register(login: login), failsWith(_badRequest));
      }
      await expectLater(
        () async => await register(cert: await h.deviceCert(other, device)),
        failsWith(_unauthenticated),
        reason: 'сертификат подписан другой учётной записью',
      );
      final forged = (await h.deviceCert(account, device)).deepCopy()
        ..signature = (await h.deviceCert(other, device)).signature;
      await expectLater(
        () => register(cert: forged),
        failsWith(_unauthenticated),
      );
      await expectLater(
        () async => await register(
          cert: await h.deviceCert(
            account,
            device,
            issuedAt: h.clock.now.add(const Duration(minutes: 6)),
          ),
        ),
        failsWith(_badRequest),
      );
      final (bundle, verifier) = await h.keyCopy(account, 'пароль');
      final (otherBundle, _) = await h.keyCopy(other, 'пароль');
      await expectLater(() => register(bundle: bundle), failsWith(_badRequest));
      await expectLater(
        () => register(verifier: verifier),
        failsWith(_badRequest),
      );
      await expectLater(
        () => register(bundle: otherBundle, verifier: verifier),
        failsWith(_badRequest),
        reason: 'KeyBundle другой учётной записи',
      );
      await expectLater(
        () => register(bundle: [1, 2, 3], verifier: verifier),
        failsWith(_badRequest),
      );
      await expectLater(
        () => register(bundle: bundle, verifier: verifier.sublist(1)),
        failsWith(_badRequest),
      );
      // Сообщение, подписанное как сертификат, но в контексте отзыва.
      final wrongContext = await SignedMessages.sign(
        h.crypto,
        account.accountSign,
        'device-revoke',
        pb.DeviceCertificate(
          accountId: account.accountId,
          deviceSign: device.publicKey,
          deviceDh: Uint8List(32),
        ),
      );
      await expectLater(
        () => register(cert: wrongContext),
        failsWith(_unauthenticated),
      );
      await register(bundle: bundle, verifier: verifier);
    });
  });

  group('устройства', () {
    test('AddDevice, ListDevices и предел 5 устройств', () async {
      final account = await h.newAccount();
      final first = await h.newKey();
      await h.register(account, first, login: 'dave');
      Future<void> add(Ed25519KeyPair device) async => await h.call(
        'AddDevice',
        pb.AddDeviceRequest(
          deviceCertificate: await h.deviceCert(account, device),
        ),
        pb.AddDeviceResponse.fromBuffer,
        key: account.accountSign,
      );
      final devices = [first];
      for (var i = 0; i < 4; i++) {
        h.clock.advance(const Duration(seconds: 1));
        final d = await h.newKey();
        await add(d);
        devices.add(d);
      }
      final sixth = await h.newKey();
      await expectLater(
        () => add(sixth),
        failsWith(pb.ErrorCode.ERROR_CODE_QUOTA_EXCEEDED),
      );
      await expectLater(() => add(devices[1]), failsWith(_alreadyExists));
      await expectLater(
        () async => await h.call(
          'AddDevice',
          pb.AddDeviceRequest(
            deviceCertificate: await h.deviceCert(account, sixth),
          ),
          pb.AddDeviceResponse.fromBuffer,
          key: first,
        ),
        failsWith(pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED),
        reason: 'устройство добавляет только ключ учётной записи',
      );

      final list = await h.call(
        'ListDevices',
        pb.ListDevicesRequest(),
        pb.ListDevicesResponse.fromBuffer,
        key: account.accountSign,
      );
      expect(list.devices, hasLength(5));
      final certs = [
        for (final d in list.devices)
          pb.DeviceCertificate.fromBuffer(d.certificate.body),
      ];
      expect(
        [for (final c in certs) bytesToHex(c.deviceSign)],
        [for (final d in devices) bytesToHex(d.publicKey)],
      );
      expect(list.devices.every((d) => d.revokedAtUnixMs == 0), isTrue);
      expect(
        list.devices.first.addedAtUnixMs.toInt(),
        inInclusiveRange(
          DbHarness.startTime.millisecondsSinceEpoch,
          DbHarness.startTime.millisecondsSinceEpoch + 1000,
        ),
      );

      // Отозванное место освобождается.
      await h.call(
        'RevokeDevice',
        pb.RevokeDeviceRequest(revocation: await h.revocation(account, first)),
        pb.RevokeDeviceResponse.fromBuffer,
        key: account.accountSign,
      );
      await add(sixth);
    });

    test(
      'отзыв: устройство больше не принимается, отзывы видны узлам',
      () async {
        final account = await h.newAccount();
        final keep = await h.newKey();
        final lost = await h.newKey();
        await h.register(account, keep, login: 'erin');
        await h.call(
          'AddDevice',
          pb.AddDeviceRequest(
            deviceCertificate: await h.deviceCert(account, lost),
          ),
          pb.AddDeviceResponse.fromBuffer,
          key: account.accountSign,
        );
        Future<void> revoke(AccountKeys by, Ed25519KeyPair device) async =>
            await h.call(
              'RevokeDevice',
              pb.RevokeDeviceRequest(
                revocation: await h.revocation(by, device),
              ),
              pb.RevokeDeviceResponse.fromBuffer,
              key: by.accountSign,
            );

        expect(await deviceCall(lost), _accepted);
        await revoke(account, lost);
        expect(await deviceCall(lost), _unauthenticated);
        expect(await deviceCall(keep), _accepted);
        await revoke(account, lost); // повтор — успех без изменений

        final stranger = await h.newAccount();
        await h.register(stranger, await h.newKey(), login: 'mallory');
        await expectLater(
          () => revoke(stranger, keep),
          failsWith(pb.ErrorCode.ERROR_CODE_NOT_FOUND),
        );
        await expectLater(
          () async => await h.call(
            'RevokeDevice',
            pb.RevokeDeviceRequest(
              revocation: await h.revocation(stranger, keep),
            ),
            pb.RevokeDeviceResponse.fromBuffer,
            key: account.accountSign,
          ),
          failsWith(_unauthenticated),
          reason: 'отзыв подписан не этой учётной записью',
        );

        final list = await h.call(
          'ListDevices',
          pb.ListDevicesRequest(),
          pb.ListDevicesResponse.fromBuffer,
          key: account.accountSign,
        );
        expect(
          [for (final d in list.devices) d.revokedAtUnixMs > 0],
          [false, true],
        );

        // Узел читает отзывы постранично.
        final node = await h.newKey();
        await h.db.run(
          (s) => s.execute(
            Sql.named(
              'INSERT INTO nodes (node_id, account_id, certificate) '
              'VALUES (@n:bytea, @a:bytea, @c:bytea)',
            ),
            parameters: {
              'n': node.publicKey,
              'a': account.accountId,
              'c': Uint8List(1),
            },
          ),
        );
        await revoke(account, keep);
        final page1 = await h.call(
          'ListRevocations',
          pb.ListRevocationsRequest(limit: 1),
          pb.ListRevocationsResponse.fromBuffer,
          key: node,
        );
        expect(page1.revocations, hasLength(1));
        expect(page1.more, isTrue);
        final page2 = await h.call(
          'ListRevocations',
          pb.ListRevocationsRequest(
            afterSequence: page1.revocations.single.sequence,
          ),
          pb.ListRevocationsResponse.fromBuffer,
          key: node,
        );
        expect(page2.more, isFalse);
        final all = [...page1.revocations, ...page2.revocations];
        expect(all.first.sequence < all.last.sequence, isTrue);
        final revoked = [
          for (final e in all)
            bytesToHex(
              (await SignedMessages.open(
                h.crypto,
                e.revocation,
                context: 'device-revoke',
                object: 'device-revoke',
                parse: pb.DeviceRevocation.fromBuffer,
              )).deviceSign,
            ),
        ];
        expect(revoked, [
          bytesToHex(lost.publicKey),
          bytesToHex(keep.publicKey),
        ]);
        final huge = await h.call(
          'ListRevocations',
          pb.ListRevocationsRequest(afterSequence: Int64.MIN_VALUE),
          pb.ListRevocationsResponse.fromBuffer,
          key: node,
        );
        expect(huge.revocations, isEmpty, reason: 'uint64 больше int8');
        await expectLater(
          () => h.call(
            'ListRevocations',
            pb.ListRevocationsRequest(),
            pb.ListRevocationsResponse.fromBuffer,
            key: account.accountSign,
          ),
          failsWith(pb.ErrorCode.ERROR_CODE_PERMISSION_DENIED),
        );
      },
    );
  });

  group('вход по паролю', () {
    late AccountKeys account;
    setUp(() async {
      account = await h.newAccount();
      await h.register(
        account,
        await h.newKey(),
        login: 'frank',
        password: 'верный пароль',
      );
    });

    test('верный пароль даёт KeyBundle, неверный — отказ', () async {
      final bundle = await h.loginWithPassword('FRANK', 'верный пароль');
      final keys = await bundle.unlock(h.crypto, 'верный пароль');
      expect(keys.accountId, account.accountId);
      await expectLater(
        () => h.loginWithPassword('frank', 'неверный пароль'),
        failsWith(_unauthenticated),
      );
    });

    test('несуществующее имя неотличимо от неверного пароля', () async {
      Future<pb.GetLoginParamsResponse> params(String login) => h.call(
        'GetLoginParams',
        pb.GetLoginParamsRequest(login: login),
        pb.GetLoginParamsResponse.fromBuffer,
      );
      final ghost = await params('ghost');
      expect(ghost.salt, hasLength(16));
      expect((await params('ghost')).salt, ghost.salt, reason: 'постоянна');
      expect((await params('ghost2')).salt, isNot(ghost.salt));
      const defaults = Argon2Params();
      expect(ghost.memoryKib, defaults.memoryKiB);
      expect(ghost.iterations, defaults.iterations);
      expect(ghost.parallelism, defaults.parallelism);
      final real = await params('frank');
      expect(real.salt, hasLength(16));
      expect(real.memoryKib, DbHarness.fastParams.memoryKiB);

      // Тот же код ошибки и для несуществующего имени.
      await expectLater(
        () => h.loginWithPassword('ghost', 'что угодно'),
        failsWith(_unauthenticated),
      );
      await expectLater(
        () => h.call(
          'GetLoginParams',
          pb.GetLoginParamsRequest(login: 'a b'),
          pb.GetLoginParamsResponse.fromBuffer,
        ),
        failsWith(_badRequest),
      );
    });

    test(
      'после 5 неудач — пауза, она растёт; успех обнуляет счётчик',
      () async {
        for (var i = 0; i < 5; i++) {
          await expectLater(
            () => h.loginWithPassword('frank', 'не тот $i'),
            failsWith(_unauthenticated),
          );
        }
        // Пауза 1 минута: даже верный пароль не проверяется.
        await expectLater(
          h.loginWithPassword('frank', 'верный пароль'),
          throwsA(
            isA<RpcFailure>()
                .having((f) => f.code, 'code', _rateLimited)
                .having(
                  (f) => f.error.retryAfterMs,
                  'retry',
                  inInclusiveRange(59000, 60000),
                ),
          ),
        );
        h.clock.advance(const Duration(minutes: 1));
        await expectLater(
          h.loginWithPassword('frank', 'снова не тот'),
          failsWith(_unauthenticated),
        );
        h.clock.advance(const Duration(minutes: 1));
        await expectLater(
          h.loginWithPassword('frank', 'верный пароль'),
          failsWith(_rateLimited),
          reason: 'вторая пауза — 2 минуты',
        );
        h.clock.advance(const Duration(minutes: 1));
        await h.loginWithPassword('frank', 'верный пароль');
        // Счётчик обнулён: снова 5 попыток без паузы.
        for (var i = 0; i < 5; i++) {
          await expectLater(
            () => h.loginWithPassword('frank', 'не тот $i'),
            failsWith(_unauthenticated),
          );
        }
        expect(LoginService.pauseAfter(4), isNull);
        expect(LoginService.pauseAfter(5), const Duration(minutes: 1));
        expect(LoginService.pauseAfter(11), const Duration(hours: 1));
        expect(LoginService.pauseAfter(1000), const Duration(hours: 1));
      },
    );

    test('паузы считаются и для несуществующих имён', () async {
      for (var i = 0; i < 5; i++) {
        await expectLater(
          () => h.loginWithPassword('ghost', 'пароль $i'),
          failsWith(_unauthenticated),
        );
      }
      await expectLater(
        () => h.loginWithPassword('ghost', 'пароль'),
        failsWith(_rateLimited),
      );
    });

    test('повтор и устаревшее доказательство отклоняются', () async {
      final params = await h.call(
        'GetLoginParams',
        pb.GetLoginParamsRequest(login: 'frank'),
        pb.GetLoginParamsResponse.fromBuffer,
      );
      final derived = await PasswordKeys.derive(
        h.crypto,
        password: 'верный пароль',
        salt: Uint8List.fromList(params.salt),
        params: DbHarness.fastParams,
      );
      final key = await PasswordLogin.loginKey(h.crypto, derived);
      Future<pb.GetKeyBundleResponse> send(int timeMs) async => await h.call(
        'GetKeyBundle',
        pb.GetKeyBundleRequest(
          login: 'frank',
          timeUnixMs: Int64(timeMs),
          authProof: await PasswordLogin.prove(
            h.crypto,
            key,
            login: 'frank',
            timeMs: timeMs,
          ),
        ),
        pb.GetKeyBundleResponse.fromBuffer,
      );
      final now = h.clock.now.millisecondsSinceEpoch;
      await send(now);
      await expectLater(
        () => send(now),
        failsWith(_unauthenticated),
        reason: 'повтор',
      );
      await expectLater(
        () => send(now - const Duration(minutes: 6).inMilliseconds),
        failsWith(_unauthenticated),
      );
      await expectLater(
        () => h.call(
          'GetKeyBundle',
          pb.GetKeyBundleRequest(login: 'frank', authProof: [1, 2]),
          pb.GetKeyBundleResponse.fromBuffer,
        ),
        failsWith(_badRequest),
      );
    });

    test('смена пароля и режим без копии', () async {
      Future<void> set(
        List<int>? bundle,
        List<int>? verifier, {
        AccountKeys? by,
      }) async => await h.call(
        'SetKeyBundle',
        pb.SetKeyBundleRequest(keyBundle: bundle, authVerifier: verifier),
        pb.SetKeyBundleResponse.fromBuffer,
        key: (by ?? account).accountSign,
      );
      final (bundle, verifier) = await h.keyCopy(account, 'новый пароль');
      await set(bundle, verifier);
      await expectLater(
        () => h.loginWithPassword('frank', 'верный пароль'),
        failsWith(_unauthenticated),
      );
      await h.loginWithPassword('frank', 'новый пароль');

      final other = await h.newAccount();
      await h.register(other, await h.newKey(), login: 'grace');
      await expectLater(
        () => set(bundle, verifier, by: other),
        failsWith(_badRequest),
        reason: 'KeyBundle чужой учётной записи',
      );

      // Без копии: на координаторе нет ни KeyBundle, ни verifier.
      await set(null, null);
      final rows = await h.db.run(
        (s) => s.execute(
          Sql.named(
            'SELECT key_bundle, auth_verifier FROM accounts '
            'WHERE account_id = @a:bytea',
          ),
          parameters: {'a': account.accountId},
        ),
      );
      expect(rows.single, [null, null]);
      await expectLater(
        () => h.loginWithPassword('frank', 'новый пароль'),
        failsWith(_unauthenticated),
      );
      final params = await h.call(
        'GetLoginParams',
        pb.GetLoginParamsRequest(login: 'frank'),
        pb.GetLoginParamsResponse.fromBuffer,
      );
      expect(params.memoryKib, const Argon2Params().memoryKiB);
    });

    test('режим без копии: переключение в обе стороны (2.4.3)', () async {
      final owner = await h.newAccount();
      final device = await h.newKey();
      Future<void> switchTo(KeyCopy copy) => h.call(
        'SetKeyBundle',
        pb.SetKeyBundleRequest(
          keyBundle: copy.keyBundle,
          authVerifier: copy.authVerifier,
        ),
        pb.SetKeyBundleResponse.fromBuffer,
        key: owner.accountSign,
      );
      Future<pb.GetLoginParamsResponse> params() => h.call(
        'GetLoginParams',
        pb.GetLoginParamsRequest(login: 'henry'),
        pb.GetLoginParamsResponse.fromBuffer,
      );

      // Регистрация сразу без копии.
      await h.call(
        'RegisterAccount',
        pb.RegisterAccountRequest(
          deviceCertificate: await h.deviceCert(owner, device),
          login: 'henry',
          keyBundle: KeyCopy.none.keyBundle,
          authVerifier: KeyCopy.none.authVerifier,
        ),
        pb.RegisterAccountResponse.fromBuffer,
        key: owner.accountSign,
      );
      final fakeSalt = (await params()).salt;
      await expectLater(
        () => h.loginWithPassword('henry', 'пароль один'),
        failsWith(_unauthenticated),
      );

      // Включение копии: вход по паролю работает, соль — из KeyBundle.
      final on = await KeyCopy.create(
        h.crypto,
        keys: owner,
        password: 'пароль один',
        params: DbHarness.fastParams,
      );
      expect(on.enabled, isTrue);
      await switchTo(on);
      expect((await params()).salt, isNot(fakeSalt));
      final unlocked = await (await h.loginWithPassword(
        'henry',
        'пароль один',
      )).unlock(h.crypto, 'пароль один');
      expect(unlocked.accountId, owner.accountId);

      // Выключение: копии нет, ответ — как для несуществующего имени.
      expect(KeyCopy.none.enabled, isFalse);
      await switchTo(KeyCopy.none);
      expect((await params()).salt, fakeSalt);
      await expectLater(
        () => h.loginWithPassword('henry', 'пароль один'),
        failsWith(_unauthenticated),
      );

      // И снова включение, уже с другим паролем.
      await switchTo(
        await KeyCopy.create(
          h.crypto,
          keys: owner,
          password: 'пароль два',
          params: DbHarness.fastParams,
        ),
      );
      await h.loginWithPassword('henry', 'пароль два');
    });

    test('предел частоты входа по IP', () async {
      await h.close();
      h = await DbHarness.create(
        config: const CoordinatorConfig(
          limits: RateLimits(loginPerMinute: 1, loginBurst: 3),
        ),
      );
      for (var i = 0; i < 3; i++) {
        await h.call(
          'GetLoginParams',
          pb.GetLoginParamsRequest(login: 'anyone'),
          pb.GetLoginParamsResponse.fromBuffer,
          ip: '198.51.100.7',
        );
      }
      await expectLater(
        () => h.call(
          'GetLoginParams',
          pb.GetLoginParamsRequest(login: 'anyone'),
          pb.GetLoginParamsResponse.fromBuffer,
          ip: '198.51.100.7',
        ),
        failsWith(_rateLimited),
      );
      await h.call(
        'GetLoginParams',
        pb.GetLoginParamsRequest(login: 'anyone'),
        pb.GetLoginParamsResponse.fromBuffer,
        ip: '198.51.100.8',
      );
    });
  });
}
