import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:himemo/features/sync/data/sync_v2_icloud_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/sync/data/sync_v2_enrollment_store.dart';
import 'package:himemo/features/sync/data/sync_v2_generation_registration.dart';

class _Cloud implements SyncV2GenerationRegistrationTransport {
  String account = 'account';
  String? proof;
  bool failPublish = false;
  bool corruptReadback = false;
  bool changeAccountAfterPublish = false;
  Object? publishError;
  Object? registrationReadError;
  final prepared = <String>[];
  final published = <String>[];
  @override
  Future<String> readCurrentAccountId() async => account;
  @override
  Future<String?> readRegistration() async {
    if (registrationReadError case final error?) throw error;
    return corruptReadback && proof != null ? 'corrupt' : proof;
  }

  @override
  Future<void> prepareGeneration(String generationId) async {
    prepared.add(generationId);
  }

  @override
  Future<void> publishRegistration(String encryptedProof) async {
    if (publishError case final error?) throw error;
    if (failPublish) throw StateError('publish failed');
    if (proof != null && proof != encryptedProof) {
      throw StateError('immutable collision');
    }
    published.add(encryptedProof);
    proof = encryptedProof;
    if (changeAccountAfterPublish) account = 'different';
  }
}

class _FaultStore extends SecureKeyValueStore {
  final backing = MemorySecureKeyValueStore();
  bool dropPending = false;
  bool failFinal = false;
  bool failProof = false;
  bool failPending = false;
  @override
  Future<String?> read(String key) => backing.read(key);
  @override
  Future<void> delete(String key) => backing.delete(key);
  @override
  Future<void> write(String key, String value) async {
    if (failPending && key.contains('pending_registration')) {
      throw StateError('pending secret write failure');
    }
    if (failProof && key.contains('verified_proof')) {
      throw StateError('proof storage failure');
    }
    if (dropPending && key.contains('pending_registration')) return;
    if (failFinal && key.endsWith('enrollment.v1')) {
      throw StateError('storage failure');
    }
    await backing.write(key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Cloud cloud;
  late SyncV2EnrollmentStore local;
  late SyncV2GenerationRegistration service;
  final admin = SecretKey(List.filled(32, 77));
  setUp(() {
    cloud = _Cloud();
    local = SyncV2EnrollmentStore(MemorySecureKeyValueStore());
    service = SyncV2GenerationRegistration(cloud, local);
  });
  Future<SyncV2PreparedRegistration> prepare() =>
      service.prepare(accountId: 'account', adminKey: admin);
  Future<void> absent() async =>
      expect(await local.readForAccount('account'), isNull);

  test('verified cache restores offline and verifies admin key without cloud calls', () async {
    final prepared = await prepare();
    addTearDown(prepared.destroy);
    final first = await service.publishPrepared(prepared);
    addTearDown(first.destroy);
    cloud.account = 'offline-account-unavailable';
    cloud.proof = 'offline-corrupt-cloud';
    final restored = await service.restoreEnrolled(accountId: 'account');
    addTearDown(restored.destroy);
    expect(
      await restored.normalKey.extractBytes(),
      await first.normalKey.extractBytes(),
    );
    expect(
      await service.exportRecoveryCode(accountId: 'account'),
      prepared.recoveryCode,
    );
    await service.verifyAdminKey(
      accountId: 'account',
      adminKey: admin,
      expectedGenerationId: prepared.generationId,
    );
    // Valid proof and key: only the explicit generation guard can reject this.
    await expectLater(
      service.verifyAdminKey(
        accountId: 'account',
        adminKey: admin,
        expectedGenerationId: 'different_generation',
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Enrollment generation changed',
        ),
      ),
    );
    final wrong = SecretKey(List.filled(32, 33));
    addTearDown(wrong.destroy);
    await expectLater(
      service.verifyAdminKey(accountId: 'account', adminKey: wrong),
      throwsA(isA<HimemoDecryptionException>()),
    );
    await expectLater(
      service.restoreEnrolled(accountId: 'account', refreshFromCloud: true),
      throwsStateError,
    );
  });

  test(
    'cache persistence failure keeps pending; resume safely completes',
    () async {
      final storage = _FaultStore()..failProof = true;
      final store = SyncV2EnrollmentStore(storage);
      final registration = SyncV2GenerationRegistration(cloud, store);
      final prepared = await registration.prepare(
        accountId: 'account',
        adminKey: admin,
      );
      addTearDown(prepared.destroy);
      await expectLater(
        registration.publishPrepared(prepared),
        throwsA(isA<SyncV2RegistrationFailure>()),
      );
      final pending = await store.readPendingRegistration();
      expect(pending, isNotNull);
      pending!.syncKey.destroy();
      storage.failProof = false;
      (await registration.resumePending()).destroy();
      expect(await store.readPendingRegistration(), isNull);
      expect(await store.readCachedProof('account'), prepared.encryptedProof);
    },
  );

  test(
    'recover winning cloud proof removes superseded same-account pending',
    () async {
      final winner = await prepare();
      addTearDown(winner.destroy);
      (await service.publishPrepared(winner)).destroy();
      final losingStore = SyncV2EnrollmentStore(MemorySecureKeyValueStore());
      final loser = SyncV2GenerationRegistration(cloud, losingStore);
      final attempt = await loser.prepare(
        accountId: 'account',
        adminKey: admin,
      );
      addTearDown(attempt.destroy);
      await expectLater(
        loser.publishPrepared(attempt),
        throwsA(isA<SyncV2RegistrationConflict>()),
      );
      final pending = await losingStore.readPendingRegistration();
      expect(pending!.generationId, attempt.generationId);
      pending.syncKey.destroy();
      (await loser.recover(winner.recoveryCode)).destroy();
      expect(await losingStore.readPendingRegistration(), isNull);
      expect(
        await losingStore.readCachedProof('account'),
        winner.encryptedProof,
      );
    },
  );

  test(
    'second device recovers the normal key without preparing or publishing',
    () async {
      final prepared = await prepare();
      addTearDown(prepared.destroy);
      final first = await service.publishPrepared(prepared);
      addTearDown(first.destroy);
      final secondStore = SyncV2EnrollmentStore(MemorySecureKeyValueStore());
      final second = await SyncV2GenerationRegistration(
        cloud,
        secondStore,
      ).recover(prepared.recoveryCode);
      addTearDown(second.destroy);
      expect(second.profileId, first.profileId);
      expect(
        await second.normalKey.extractBytes(),
        await first.normalKey.extractBytes(),
      );
      expect(cloud.prepared, [prepared.generationId]);
      expect(cloud.published, [prepared.encryptedProof]);
      final enrollment = await secondStore.readForAccount('account');
      expect(enrollment!.generationId, prepared.generationId);
      enrollment.syncKey.destroy();
    },
  );

  test(
    'account singleton is first writer wins and retries retain exact proof',
    () async {
      final first = await prepare();
      final second = await prepare();
      addTearDown(first.destroy);
      addTearDown(second.destroy);
      (await service.publishPrepared(first)).destroy();
      (await service.publishPrepared(first)).destroy();
      final otherStore = SyncV2EnrollmentStore(MemorySecureKeyValueStore());
      await expectLater(
        SyncV2GenerationRegistration(cloud, otherStore).publishPrepared(second),
        throwsA(isA<SyncV2RegistrationConflict>()),
      );
      expect(await otherStore.readForAccount('account'), isNull);
      expect(cloud.published, [first.encryptedProof, first.encryptedProof]);
      expect(cloud.proof, first.encryptedProof);
      final writes = cloud.prepared.length;
      await expectLater(
        service.publishPrepared(second),
        throwsA(isA<SyncV2RegistrationFailure>()),
      );
      expect(cloud.prepared.length, writes);
    },
  );

  for (final failure in ['publish', 'readback', 'account']) {
    test('$failure failure cannot enroll locally', () async {
      final prepared = await prepare();
      addTearDown(prepared.destroy);
      cloud.failPublish = failure == 'publish';
      cloud.corruptReadback = failure == 'readback';
      cloud.changeAccountAfterPublish = failure == 'account';
      await expectLater(
        service.publishPrepared(prepared),
        throwsA(isA<SyncV2RegistrationFailure>()),
      );
      await absent();
    });
  }

  test('safe registration failure keeps pending proof retryable', () async {
    final prepared = await prepare();
    addTearDown(prepared.destroy);
    cloud.publishError = PlatformException(
      code: '11',
      message:
          'private diagnostic ${prepared.recoveryCode} ${prepared.encryptedProof}',
    );

    SyncV2RegistrationFailure? failure;
    try {
      await service.publishPrepared(prepared);
      fail('Expected registration to fail');
    } on SyncV2RegistrationFailure catch (error) {
      failure = error;
    }
    expect(failure.stage, SyncV2RegistrationStage.publishRegistration);
    expect(failure.safeCode, '11');
    expect(failure.toString(), isNot(contains(prepared.recoveryCode)));
    expect(failure.toString(), isNot(contains(prepared.encryptedProof)));
    expect(failure.toString(), isNot(contains('private diagnostic')));

    final pending = await local.readPendingRegistration();
    expect(pending, isNotNull);
    expect(pending!.encryptedProof, prepared.encryptedProof);
    pending.syncKey.destroy();

    cloud.publishError = null;
    (await service.resumePending()).destroy();
    expect(await local.readPendingRegistration(), isNull);
  });

  test(
    'unknown platform code and pending storage failure use safe codes',
    () async {
      final prepared = await prepare();
      addTearDown(prepared.destroy);
      cloud.registrationReadError = PlatformException(
        code: 'account-id-secret',
        message: prepared.recoveryCode,
      );
      await expectLater(
        service.publishPrepared(prepared),
        throwsA(
          isA<SyncV2RegistrationFailure>()
              .having(
                (error) => error.stage,
                'stage',
                SyncV2RegistrationStage.readRegistration,
              )
              .having((error) => error.safeCode, 'safeCode', 'platform_error'),
        ),
      );

      final storage = _FaultStore()..failPending = true;
      final store = SyncV2EnrollmentStore(storage);
      final registration = SyncV2GenerationRegistration(cloud, store);
      cloud.registrationReadError = null;
      await expectLater(
        registration.publishPrepared(prepared),
        throwsA(
          isA<SyncV2RegistrationFailure>()
              .having(
                (error) => error.stage,
                'stage',
                SyncV2RegistrationStage.persistPending,
              )
              .having((error) => error.safeCode, 'safeCode', 'state_error')
              .having(
                (error) => error.toString(),
                'safe message',
                isNot(contains('pending secret write failure')),
              ),
        ),
      );
      expect(cloud.prepared, isEmpty);
      expect(cloud.published, isEmpty);
    },
  );

  test('wrong account is rejected before cloud writes', () async {
    final prepared = await prepare();
    addTearDown(prepared.destroy);
    cloud.account = 'other';
    await expectLater(
      service.publishPrepared(prepared),
      throwsA(isA<SyncV2RegistrationFailure>()),
    );
    expect(cloud.prepared, isEmpty);
    expect(cloud.published, isEmpty);
    await absent();
  });

  test(
    'invalid codes, wrong keys and wrong generations never enroll',
    () async {
      final prepared = await prepare();
      addTearDown(prepared.destroy);
      (await service.publishPrepared(prepared)).destroy();
      final raw = Map<String, dynamic>.from(
        jsonDecode(utf8.decode(base64Url.decode(prepared.recoveryCode))) as Map,
      );
      final badCodes = [
        '!',
        'a' * 4097,
        for (final patch in [
          {'version': 2},
          {'version': 1.0},
          {'format': 'other'},
          {
            'key': base64UrlEncode([1]),
          },
          {'key': base64UrlEncode(List.filled(32, 3))},
          {'generation': 'wrong'},
          {'account': 'other'},
        ])
          base64UrlEncode(utf8.encode(jsonEncode({...raw, ...patch}))),
      ];
      for (final code in badCodes) {
        final store = SyncV2EnrollmentStore(MemorySecureKeyValueStore());
        await expectLater(
          SyncV2GenerationRegistration(cloud, store).recover(code),
          throwsA(anything),
        );
        expect(await store.readForAccount('account'), isNull);
      }
      expect(cloud.published, hasLength(1));
    },
  );

  test('corrupt committed proof is rejected without registration', () async {
    final prepared = await prepare();
    addTearDown(prepared.destroy);
    cloud.proof = prepared.encryptedProof;
    cloud.corruptReadback = true;
    await expectLater(
      service.recover(prepared.recoveryCode),
      throwsA(isA<HimemoDecryptionException>()),
    );
    await absent();
  });

  test(
    'sync recovery key cannot decrypt administrator wrap or cross its purpose',
    () async {
      final prepared = await prepare();
      addTearDown(prepared.destroy);
      final code = jsonDecode(
        utf8.decode(base64Url.decode(prepared.recoveryCode)),
      ) as Map;
      expect(code.keys.toSet(), {
        'version',
        'account',
        'generation',
        'key',
        'format',
      });
      final sync = SecretKey(base64Url.decode(code['key'] as String));
      addTearDown(sync.destroy);
      final encryption = EncryptionService();
      List<int> context(String purpose, [String? profile, String? keyId]) =>
          utf8.encode(
            jsonEncode([
              'himemo-sync-v2-registration',
              1,
              'account',
              prepared.generationId,
              purpose,
              profile,
              keyId,
            ]),
          );
      final manifest = jsonDecode(
        utf8.decode(
          await encryption.decryptBytes(
            encodedPayload: prepared.encryptedProof,
            secretKey: sync,
            additionalData: context('committed-manifest'),
          ),
        ),
      ) as Map;
      final aad = context(
        'normal-admin-wrap',
        manifest['normalProfileId'] as String,
        manifest['keyId'] as String,
      );
      final adminWrap = manifest['normalAdminWrap'] as String;
      await expectLater(
        encryption.decryptBytes(
          encodedPayload: adminWrap,
          secretKey: sync,
          additionalData: aad,
        ),
        throwsA(isA<HimemoDecryptionException>()),
      );
      final normal = await encryption.decryptBytes(
        encodedPayload: adminWrap,
        secretKey: admin,
        additionalData: aad,
      );
      expect(normal, hasLength(32));
      await expectLater(
        encryption.decryptBytes(
          encodedPayload: adminWrap,
          secretKey: admin,
          additionalData: context(
            'normal-sync-wrap',
            manifest['normalProfileId'] as String,
            manifest['keyId'] as String,
          ),
        ),
        throwsA(isA<HimemoDecryptionException>()),
      );
    },
  );
  test(
    'metadata adapter handles only absent record and zone and scopes writes',
    () async {
      const channel = MethodChannel('registration-test');
      final calls = <MethodCall>[];
      var code = '11';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'cloudKitV2FetchHeader') {
              throw PlatformException(code: code);
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final adapter = SyncV2ICloudGenerationRegistrationTransport(
        SyncV2ICloudTransport(accountId: 'account', channel: channel),
        metadataGenerationId: 'dev_fresh',
      );
      expect(await adapter.readRegistration(), isNull);
      code = '26';
      expect(await adapter.readRegistration(), isNull);
      code = '28';
      await expectLater(
        adapter.readRegistration(),
        throwsA(isA<SyncV2CloudDataDeleted>()),
      );
      code = '9';
      await expectLater(
        adapter.readRegistration(),
        throwsA(isA<PlatformException>()),
      );
      await adapter.prepareGeneration('actual');
      await adapter.publishRegistration('proof');
      expect(
        calls
            .where((call) => call.method == 'cloudKitV2Prepare')
            .map((call) => (call.arguments as Map)['generationId']),
        ['actual', 'dev_fresh'],
      );
      final publication = calls.last.arguments as Map;
      expect(publication['generationId'], 'dev_fresh');
      expect(publication['id'], 'active-generation-v1');
      expect(publication['header'], 'proof');
      expect(publication['payload'], isNull);
      await expectLater(
        adapter.prepareGeneration('dev_fresh'),
        throwsArgumentError,
      );
    },
  );
  test(
    'authenticated malformed manifests and oversized proofs cannot enroll',
    () async {
      final prepared = await prepare();
      addTearDown(prepared.destroy);
      final code = jsonDecode(
        utf8.decode(base64Url.decode(prepared.recoveryCode)),
      ) as Map;
      final key = SecretKey(base64Url.decode(code['key'] as String));
      addTearDown(key.destroy);
      final encryption = EncryptionService();
      final aad = utf8.encode(
        jsonEncode([
          'himemo-sync-v2-registration',
          1,
          'account',
          prepared.generationId,
          'committed-manifest',
          null,
          null,
        ]),
      );
      final manifest = jsonDecode(
        utf8.decode(
          await encryption.decryptBytes(
            encodedPayload: prepared.encryptedProof,
            secretKey: key,
            additionalData: aad,
          ),
        ),
      ) as Map;
      for (final patch in [
        {'version': 1.0},
        {'normalAdminWrap': ''},
        {'normalAdminWrap': 'x' * 4097},
        {
          'normalSyncWrap': jsonEncode({
            'version': 1,
            'nonce': base64Encode(List.filled(12, 0)),
            'cipherText': base64Encode(List.filled(31, 0)),
            'mac': base64Encode(List.filled(16, 0)),
          }),
        },
      ]) {
        cloud.proof = await encryption.encryptBytes(
          clearBytes: utf8.encode(jsonEncode({...manifest, ...patch})),
          secretKey: key,
          additionalData: aad,
        );
        await expectLater(
          service.recover(prepared.recoveryCode),
          throwsFormatException,
        );
        await absent();
      }
      cloud.proof = 'x' * 65537;
      await expectLater(
        service.recover(prepared.recoveryCode),
        throwsFormatException,
      );
      await absent();
    },
  );
  test(
    'pending storage must confirm durability before any cloud write',
    () async {
      final backing = _FaultStore()..dropPending = true;
      final store = SyncV2EnrollmentStore(backing);
      final registration = SyncV2GenerationRegistration(cloud, store);
      final prepared = await registration.prepare(
        accountId: 'account',
        adminKey: admin,
      );
      addTearDown(prepared.destroy);
      await expectLater(
        registration.publishPrepared(prepared),
        throwsA(isA<SyncV2RegistrationFailure>()),
      );
      expect(cloud.prepared, isEmpty);
      expect(cloud.published, isEmpty);
      expect(await store.readForAccount('account'), isNull);
    },
  );

  test(
    'fresh service resumes original proof after cloud commit and local failure',
    () async {
      final backing = _FaultStore()..failFinal = true;
      final store = SyncV2EnrollmentStore(backing);
      final registration = SyncV2GenerationRegistration(cloud, store);
      final prepared = await registration.prepare(
        accountId: 'account',
        adminKey: admin,
      );
      final proof = prepared.encryptedProof;
      final generation = prepared.generationId;
      await expectLater(
        registration.publishPrepared(prepared),
        throwsA(isA<SyncV2RegistrationFailure>()),
      );
      prepared.destroy();
      expect(cloud.proof, proof);
      expect(await store.readForAccount('account'), isNull);
      final pending = await store.readPendingRegistration();
      expect(pending!.encryptedProof, proof);
      pending.syncKey.destroy();
      backing.failFinal = false;
      final restartedStore = SyncV2EnrollmentStore(backing);
      final restarted = SyncV2GenerationRegistration(cloud, restartedStore);
      final profile = await restarted.resumePending();
      addTearDown(profile.destroy);
      expect(profile.access.generationId, generation);
      expect(cloud.published, [proof, proof]);
      expect(await restartedStore.readPendingRegistration(), isNull);
      final finalEnrollment = await restartedStore.readForAccount('account');
      expect(finalEnrollment!.generationId, generation);
      finalEnrollment.syncKey.destroy();
    },
  );

  test(
    'pending survives restart and account mismatch after lost readback',
    () async {
      final prepared = await prepare();
      addTearDown(prepared.destroy);
      cloud.corruptReadback = true;
      await expectLater(
        service.publishPrepared(prepared),
        throwsA(isA<SyncV2RegistrationFailure>()),
      );
      cloud.account = 'other';
      await expectLater(
        SyncV2GenerationRegistration(cloud, local).resumePending(),
        throwsA(isA<SyncV2RegistrationFailure>()),
      );
      final pending = await local.readPendingRegistration();
      expect(pending!.encryptedProof, prepared.encryptedProof);
      pending.syncKey.destroy();
      cloud.account = 'account';
      cloud.corruptReadback = false;
      (await SyncV2GenerationRegistration(
        cloud,
        local,
      ).resumePending()).destroy();
      expect(await local.readPendingRegistration(), isNull);
      expect(cloud.published, [
        prepared.encryptedProof,
        prepared.encryptedProof,
      ]);
    },
  );

  test('generation prefixes are scoped and bounded', () async {
    for (final prefix in ['', 'bad prefix', 'x' * 48]) {
      expect(
        () => SyncV2GenerationRegistration(
          cloud,
          local,
          generationPrefix: prefix,
        ),
        throwsArgumentError,
      );
    }
    final registration = SyncV2GenerationRegistration(
      cloud,
      local,
      generationPrefix: 'dev_fresh_g',
    );
    final prepared = await registration.prepare(
      accountId: 'account',
      adminKey: admin,
    );
    addTearDown(prepared.destroy);
    expect(prepared.generationId, startsWith('dev_fresh_g_'));
  });
}
