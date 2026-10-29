import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:himemo/features/security/data/app_pin_lock_store.dart';
import 'package:himemo/features/security/data/secret_verifier_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:himemo/features/security/data/authentication_throttle.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/master_key_service.dart';
import 'package:himemo/features/security/data/private_vault_secret_store.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:himemo/features/sync/data/sync_bundle_key_service.dart';

class _NoConfirmStore extends MemorySecureKeyValueStore {
  @override
  Future<String?> read(String key) async => null;
}

class _DropFirstWriteStore extends MemorySecureKeyValueStore {
  bool _drop = true;

  @override
  Future<void> write(String key, String value) async {
    if (_drop) {
      _drop = false;
      return;
    }
    await super.write(key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MasterKeyService concurrency and persistence', () {
    test('separate instances share one creation and identical bytes', () async {
      final store = MemorySecureKeyValueStore();
      var creations = 0;
      List<int> factory() {
        creations++;
        return List<int>.generate(32, (i) => i + 1);
      }

      final services = List.generate(
        8,
        (_) => MasterKeyService(secureStore: store, keyFactory: factory),
      );
      final keys = await Future.wait(
        services.map((service) => service.obtainOrCreate()),
      );
      final bytes = await Future.wait(keys.map((key) => key.extractBytes()));
      expect(creations, 1);
      for (final value in bytes.skip(1)) {
        expect(value, bytes.first);
      }
    });

    test('invalid stored or generated key fails without overwriting', () async {
      final store = MemorySecureKeyValueStore();
      await store.write('security.master_key.v1', base64Encode([1, 2, 3]));
      var creations = 0;
      final service = MasterKeyService(
        secureStore: store,
        keyFactory: () {
          creations++;
          return List.filled(32, 9);
        },
      );
      await expectLater(service.obtainOrCreate(), throwsFormatException);
      expect(creations, 0);
      expect(
        await store.read('security.master_key.v1'),
        base64Encode([1, 2, 3]),
      );

      final emptyStore = MemorySecureKeyValueStore();
      final invalidFactory = MasterKeyService(
        secureStore: emptyStore,
        keyFactory: () => List.filled(31, 7),
      );
      await expectLater(invalidFactory.obtainOrCreate(), throwsStateError);
      expect(await emptyStore.read('security.master_key.v1'), isNull);
    });

    test('unconfirmed write fails and a later retry can persist', () async {
      final store = _DropFirstWriteStore();
      final service = MasterKeyService(
        secureStore: store,
        keyFactory: () => List.filled(32, 4),
      );
      await expectLater(service.obtainOrCreate(), throwsStateError);
      expect(await store.read('security.master_key.v1'), isNull);
      final key = await service.obtainOrCreate();
      expect(await key.extractBytes(), List.filled(32, 4));
    });
  });

  group('SyncBundleKeyService', () {
    test('cross-instance generation and import serialize on the shared store', () async {
      final store = MemorySecureKeyValueStore();
      var creations = 0;
      final generated = SyncBundleKeyService(
        secureStore: store,
        keyFactory: () {
          creations++;
          return List.filled(32, 3);
        },
      );
      final importing = SyncBundleKeyService(
        secureStore: store,
        keyFactory: () {
          creations++;
          return List.filled(32, 8);
        },
      );
      final code =
          '${SyncBundleKeyService.backupCodePrefix}${base64Encode(List.filled(32, 6))}';
      final results = await Future.wait([
        generated.obtainOrCreate(),
        importing.importBackupCode(code),
      ]);
      expect(creations, lessThanOrEqualTo(1));
      final existing = await importing.exportExistingBackupCode();
      expect(existing, code);
      expect(results, hasLength(2));
    });

    test('existing-only reads do not generate a key', () async {
      var creations = 0;
      final service = SyncBundleKeyService(
        secureStore: MemorySecureKeyValueStore(),
        keyFactory: () {
          creations++;
          return List.filled(32, 2);
        },
      );
      expect(await service.existingFullFingerprint(), isNull);
      expect(await service.exportExistingBackupCode(), isNull);
      await expectLater(service.requireExisting(), throwsStateError);
      expect(creations, 0);
    });
  });

  group('AuthenticationThrottle', () {
    test(
      'corrupt counters recover with a persisted thirty second block',
      () async {
        for (final raw in [
          'broken',
          '[]',
          '{"failures":"5"}',
          '{"failures":-1,"blockedUntil":0}',
        ]) {
          final store = MemorySecureKeyValueStore();
          await store.write('corrupt', raw);
          var now = DateTime.utc(2026, 10, 29);
          final throttle = AuthenticationThrottle(
            store: store,
            storageKey: 'corrupt',
            now: () => now,
          );
          var checks = 0;
          Future<bool> check() async {
            checks++;
            return true;
          }

          await expectLater(
            throttle.verify(check),
            throwsA(isA<AuthenticationThrottledException>()),
          );
          expect(checks, 0);
          expect(jsonDecode((await store.read('corrupt'))!)['failures'], 5);
          now = now.add(const Duration(seconds: 31));
          expect(await throttle.verify(check), isTrue);
        }
      },
    );

    test('backward clock wait is capped and persisted', () async {
      final store = MemorySecureKeyValueStore();
      final now = DateTime.utc(2026, 10, 29);
      await store.write(
        'clock',
        jsonEncode({
          'failures': 12,
          'blockedUntil': now
              .add(const Duration(days: 1))
              .millisecondsSinceEpoch,
        }),
      );
      final throttle = AuthenticationThrottle(
        store: store,
        storageKey: 'clock',
        now: () => now,
      );
      await expectLater(
        throttle.verify(() async => true),
        throwsA(isA<AuthenticationThrottledException>()),
      );
      expect(
        jsonDecode((await store.read('clock'))!)['blockedUntil'],
        now.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      );
    });

    test(
      'persists exponential blocks across instances and resets on success',
      () async {
        final store = MemorySecureKeyValueStore();
        var now = DateTime.utc(2026, 10, 29);
        AuthenticationThrottle create() => AuthenticationThrottle(
          store: store,
          storageKey: 'auth.attempts',
          now: () => now,
        );

        for (var i = 0; i < 5; i++) {
          expect(await create().verify(() async => false), isFalse);
        }
        await expectLater(
          create().verify(() async => true),
          throwsA(isA<AuthenticationThrottledException>()),
        );
        now = now.add(const Duration(seconds: 31));
        expect(await create().verify(() async => false), isFalse);
        final next = AuthenticationThrottle(
          store: store,
          storageKey: 'auth.attempts',
          now: () => now,
        );
        await expectLater(
          next.verify(() async => true),
          throwsA(isA<AuthenticationThrottledException>()),
        );
        final state = jsonDecode(
          (await store.read('auth.attempts'))!,
        ) as Map<String, dynamic>;
        expect(state['blockedUntil'], now.millisecondsSinceEpoch + 60000);

        now = now.add(const Duration(seconds: 61));
        expect(await create().verify(() async => true), isTrue);
        expect(await store.read('auth.attempts'), isNull);
      },
    );

    test(
      'parallel failures serialize and persistence failure fails closed',
      () async {
        final store = MemorySecureKeyValueStore();
        final throttle = AuthenticationThrottle(
          store: store,
          storageKey: 'parallel',
        );
        var checks = 0;
        await Future.wait(
          List.generate(12, (_) async {
            try {
              await throttle.verify(() async {
                checks++;
                return false;
              });
            } on AuthenticationThrottledException {
              // Blocked attempts must not run the credential check.
            }
          }),
        );
        final state =
            jsonDecode((await store.read('parallel'))!) as Map<String, dynamic>;
        expect(state['failures'], 5);
        expect(checks, 5);

        final noConfirm = AuthenticationThrottle(
          store: _NoConfirmStore(),
          storageKey: 'no-confirm',
        );
        await expectLater(
          noConfirm.verify(() async => false),
          throwsStateError,
        );
      },
    );
  });

  test(
    'PIN attempts persist separately without moving its existing verifier',
    () async {
      SharedPreferences.setMockInitialValues({});
      final counters = MemorySecureKeyValueStore();
      final encryption = EncryptionService(
        kdf: Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 10, bits: 256),
      );
      AppPinLockStore create() => AppPinLockStore(
        encryptionService: encryption,
        attemptStore: counters,
      );
      await create().configure('1234');
      final prefs = await SharedPreferences.getInstance();
      final original = prefs.getString('settings.web_app_pin.v1');
      for (var i = 0; i < 5; i++) {
        expect(await create().verify('9999'), false);
      }
      await expectLater(
        create().verify('1234'),
        throwsA(isA<AuthenticationThrottledException>()),
      );
      expect(prefs.getString('settings.web_app_pin.v1'), original);
      expect(
        await counters.read('settings.web_app_pin.v1.attempts.v1'),
        isNotNull,
      );
    },
  );

  test('cover secret instances share the persistent attempt limit', () async {
    final secure = MemorySecureKeyValueStore();
    final encryption = EncryptionService(
      kdf: Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 10, bits: 256),
    );
    SecretVerifierStore create() => SecretVerifierStore(
      secureStore: secure,
      encryptionService: encryption,
      storageKey: 'cover',
    );
    await create().configure('cover-secret');
    for (var i = 0; i < 5; i++) {
      expect(await create().verify('incorrect'), false);
    }
    await expectLater(
      create().verify('cover-secret'),
      throwsA(isA<AuthenticationThrottledException>()),
    );
  });

  group('PrivateVaultSecretStore migration', () {
    late SharedPreferences prefs;
    late EncryptionService encryption;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      encryption = EncryptionService();
    });

    Future<void> setLegacySecret() async {
      final salt = encryption.generateSalt();
      final verifier = await encryption.deriveSecretVerifier(
        secret: 'vault-pin',
        salt: salt,
      );
      await prefs.setString('security.private_vault_salt', base64Encode(salt));
      await prefs.setString('security.private_vault_digest', verifier);
    }

    test('unconfirmed migration retains legacy values and throws', () async {
      await setLegacySecret();
      final store = PrivateVaultSecretStore(
        secureStore: _NoConfirmStore(),
        encryptionService: encryption,
        sharedPreferencesProvider: () async => prefs,
      );
      await expectLater(store.hasSecret(), throwsStateError);
      expect(prefs.getString('security.private_vault_salt'), isNotNull);
      expect(prefs.getString('security.private_vault_digest'), isNotNull);
    });

    test(
      'successful migration removes legacy values and verifies secret',
      () async {
        await setLegacySecret();
        final store = PrivateVaultSecretStore(
          secureStore: MemorySecureKeyValueStore(),
          encryptionService: encryption,
          sharedPreferencesProvider: () async => prefs,
        );
        expect(await store.hasSecret(), isTrue);
        expect(prefs.getString('security.private_vault_salt'), isNull);
        expect(prefs.getString('security.private_vault_digest'), isNull);
        expect(await store.verify('vault-pin'), isTrue);
      },
    );
  });
}
