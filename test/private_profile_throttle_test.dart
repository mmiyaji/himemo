@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/native.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/home/presentation/home_providers.dart';
import 'package:himemo/features/security/data/encrypted_attachment_store.dart';
import 'package:himemo/features/security/data/encrypted_note_database.dart';
import 'package:himemo/features/security/data/encrypted_note_store.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/master_key_service.dart';
import 'package:himemo/features/security/data/profile_data_key_service.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'one password guess across profiles increments the shared counter once',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      await harness.seedProfiles();

      final result = await harness.container
          .read(privateProfileUnlockControllerProvider.notifier)
          .unlockWithPassword('not-a-profile-password');

      expect(result, isNull);
      final raw = await harness.secureStore.read(
        'security.private_profiles.attempts.v1',
      );
      expect(raw, isNotNull);
      expect(jsonDecode(raw!)['failures'], 1);
    },
  );

  test(
    'legacy and modern profiles share only the outer attempt counter',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      await harness.seedProfiles();
      await harness.container
          .read(privateVaultSecretControllerProvider.notifier)
          .configure('legacy-password');
      final controller = harness.container.read(
        privateProfileUnlockControllerProvider.notifier,
      );
      // A stale inner block must not affect the combined profile unlock path.
      await harness.secureStore.write(
        'security.private_vault.verifier.v1.attempts.v1',
        jsonEncode({
          'failures': 5,
          'blockedUntil': DateTime.now()
              .add(const Duration(hours: 1))
              .millisecondsSinceEpoch,
        }),
      );
      for (var i = 0; i < 6; i++) {
        expect(await controller.unlockWithPassword('wrong'), isNull);
        expect(
          (await controller.unlockWithPassword('alpha-password'))?.isLegacy,
          isFalse,
        );
        expect(
          await harness.secureStore.read(
            'security.private_profiles.attempts.v1',
          ),
          isNull,
        );
      }
      expect(
        (await controller.unlockWithPassword('legacy-password'))?.isLegacy,
        isTrue,
      );
    },
  );

  test(
    'valid password switching between profiles does not accumulate failures',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      final profiles = await harness.seedProfiles();
      final controller = harness.container.read(
        privateProfileUnlockControllerProvider.notifier,
      );

      expect(
        (await controller.unlockWithPassword('alpha-password'))?.vaultId,
        profiles.alphaVaultId,
      );
      expect(
        await harness.secureStore.read('security.private_profiles.attempts.v1'),
        isNull,
      );
      expect(
        (await controller.unlockWithPassword('beta-password'))?.vaultId,
        profiles.betaVaultId,
      );
      expect(
        await harness.secureStore.read('security.private_profiles.attempts.v1'),
        isNull,
      );
    },
  );

  test('shared persisted throttle blocks the sixth guess', () async {
    final harness = await _Harness.create();
    addTearDown(harness.dispose);
    final profiles = await harness.seedProfiles();
    final controller = harness.container.read(
      privateProfileUnlockControllerProvider.notifier,
    );

    for (var attempt = 0; attempt < 5; attempt++) {
      expect(
        await controller.unlockWithPassword('wrong-password-$attempt'),
        isNull,
      );
    }
    final beforeSixth = jsonDecode(
      (await harness.secureStore.read(
        'security.private_profiles.attempts.v1',
      ))!,
    ) as Map<String, dynamic>;
    expect(beforeSixth['failures'], 5);
    expect(await controller.unlockWithPassword('wrong-password-sixth'), isNull);
    expect(await controller.unlockWithPassword('alpha-password'), isNull);
    expect(harness.keys.isProfileUnlocked(profiles.alphaVaultId), isFalse);
  });

  test(
    'device authentication still delegates with its existing arguments',
    () async {
      final gateway = _RecordingDeviceAuth();
      final container = ProviderContainer(
        overrides: [deviceAuthGatewayProvider.overrideWithValue(gateway)],
      );
      addTearDown(container.dispose);

      expect(
        await container
            .read(deviceAuthControllerProvider.notifier)
            .authenticate(reason: 'Unlock HiMemo'),
        isTrue,
      );
      expect(gateway.reason, 'Unlock HiMemo');
      expect(gateway.biometricOnly, isFalse);
    },
  );
}

class _RecordingDeviceAuth implements DeviceAuthGateway {
  String? reason;
  bool? biometricOnly;

  @override
  Future<DeviceAuthState> checkAvailability() async => const DeviceAuthState(
    availability: DeviceAuthAvailability.available,
    methods: ['Face ID'],
  );

  @override
  Future<bool> authenticate({
    required String reason,
    bool biometricOnly = false,
  }) async {
    this.reason = reason;
    this.biometricOnly = biometricOnly;
    return true;
  }
}

class _Harness {
  _Harness({
    required this.container,
    required this.directory,
    required this.database,
    required this.keys,
    required this.secureStore,
  });

  final ProviderContainer container;
  final Directory directory;
  final EncryptedNoteDatabase database;
  final ProfileDataKeyService keys;
  final MemorySecureKeyValueStore secureStore;

  static Future<_Harness> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'himemo-profile-throttle-',
    );
    final secureStore = MemorySecureKeyValueStore();
    final encryption = EncryptionService(
      random: Random(17),
      kdf: Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 10, bits: 256),
    );
    final master = MasterKeyService(
      secureStore: secureStore,
      keyFactory: encryption.generateKeyBytes,
    );
    final keys = ProfileDataKeyService(
      secureStore: secureStore,
      encryptionService: encryption,
      normalMasterKeyService: master,
    );
    final database = EncryptedNoteDatabase(executor: NativeDatabase.memory());
    final notes = EncryptedNoteStore(
      encryptionService: encryption,
      masterKeyService: master,
      profileDataKeyService: keys,
      database: database,
      directoryProvider: () async => directory,
      sharedPreferencesProvider: SharedPreferences.getInstance,
    );
    final attachments = EncryptedAttachmentStore(
      encryptionService: encryption,
      masterKeyService: master,
      profileDataKeyService: keys,
      directoryProvider: () async => directory,
      sharedPreferencesProvider: SharedPreferences.getInstance,
    );
    final container = ProviderContainer(
      overrides: [
        secureKeyValueStoreProvider.overrideWithValue(secureStore),
        encryptionServiceProvider.overrideWithValue(encryption),
        masterKeyServiceProvider.overrideWithValue(master),
        profileDataKeyServiceProvider.overrideWithValue(keys),
        encryptedNoteDatabaseProvider.overrideWithValue(database),
        encryptedNoteStoreProvider.overrideWithValue(notes),
        encryptedAttachmentStoreProvider.overrideWithValue(attachments),
      ],
    );
    await container.read(notesControllerProvider.notifier).restoreCompleted;
    return _Harness(
      container: container,
      directory: directory,
      database: database,
      keys: keys,
      secureStore: secureStore,
    );
  }

  Future<_Profiles> seedProfiles() async {
    final profiles = container.read(
      privateMemoProfilesControllerProvider.notifier,
    );
    await profiles.addProfile(name: 'Alpha', password: 'alpha-password');
    await profiles.addProfile(name: 'Beta', password: 'beta-password');
    final all = container.read(privateMemoProfilesProvider);
    return _Profiles(
      alphaVaultId: all
          .singleWhere((profile) => profile.name == 'Alpha')
          .vaultId,
      betaVaultId: all.singleWhere((profile) => profile.name == 'Beta').vaultId,
    );
  }

  Future<void> dispose() async {
    container.dispose();
    await database.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

class _Profiles {
  const _Profiles({required this.alphaVaultId, required this.betaVaultId});
  final String alphaVaultId;
  final String betaVaultId;
}
