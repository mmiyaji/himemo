import 'dart:math';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/master_key_service.dart';
import 'package:himemo/features/security/data/profile_data_key_service.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';

class DelayedProfileReadStore implements SecureKeyValueStore {
  DelayedProfileReadStore(this._inner);

  final SecureKeyValueStore _inner;
  bool delayNextProfileRead = false;
  final profileReadEntered = Completer<void>();
  final releaseProfileRead = Completer<void>();
  bool delayNextAdminRead = false;
  final adminReadEntered = Completer<void>();
  final releaseAdminRead = Completer<void>();

  @override
  Future<String?> read(String key) async {
    if (delayNextProfileRead &&
        key == 'security.profile_data_key.v1.private_profile:race') {
      delayNextProfileRead = false;
      profileReadEntered.complete();
      await releaseProfileRead.future;
    }
    if (delayNextAdminRead &&
        key == 'security.profile_data_key.v1..admin.private_profile:race') {
      delayNextAdminRead = false;
      adminReadEntered.complete();
      await releaseAdminRead.future;
    }
    return _inner.read(key);
  }

  @override
  Future<void> write(String key, String value) => _inner.write(key, value);

  @override
  Future<void> delete(String key) => _inner.delete(key);
}

void main() {
  ProfileDataKeyService service(
    SecureKeyValueStore store, {
    bool enableLocalAdminAccess = true,
  }) {
    final encryption = EncryptionService(random: Random(901));
    return ProfileDataKeyService(
      secureStore: store,
      encryptionService: encryption,
      enableLocalAdminAccess: enableLocalAdminAccess,
      normalMasterKeyService: MasterKeyService(
        secureStore: store,
        keyFactory: encryption.generateKeyBytes,
      ),
    );
  }

  test('unsupported environments keep profile keys password-only', () async {
    final store = MemorySecureKeyValueStore();
    final keys = service(store, enableLocalAdminAccess: false);
    const vaultId = 'private_profile:web';
    await keys.configureProfile(vaultId: vaultId, password: 'password');
    keys.lockAllPrivateProfiles();
    expect(
      await store.read('security.profile_data_key.v1..admin.$vaultId'),
      isNull,
    );
    expect(await keys.unlockProfilesForAdmin([vaultId]), [vaultId]);
    expect(keys.isProfileUnlocked(vaultId), isFalse);
    expect(
      await keys.unlockProfile(vaultId: vaultId, password: 'password'),
      isTrue,
    );
    expect(
      await store.read('security.profile_data_key.v1..admin.$vaultId'),
      isNull,
    );
  });

  test('restores all configured profiles from local admin wraps', () async {
    final store = MemorySecureKeyValueStore();
    final first = service(store);
    await first.configureProfile(vaultId: 'private_profile:a', password: 'a');
    final expectedA = await (await first.keyForVault(
      'private_profile:a',
    ))!.extractBytes();
    await first.configureProfile(vaultId: 'private_profile:b', password: 'b');
    first.lockAllPrivateProfiles();

    final restored = service(store);
    expect(
      await restored.unlockProfilesForAdmin([
        'private_profile:a',
        'private_profile:b',
      ]),
      isEmpty,
    );
    expect(restored.isProfileUnlocked('private_profile:a'), isTrue);
    expect(restored.isProfileUnlocked('private_profile:b'), isTrue);
    final actualA = await (await restored.keyForVault(
      'private_profile:a',
    ))!.extractBytes();
    expect(actualA, expectedA);
  });

  test(
    'password verification does not unlock or create an admin wrap',
    () async {
      final store = MemorySecureKeyValueStore();
      final keys = service(store);
      const vaultId = 'private_profile:verify';
      await keys.configureProfile(vaultId: vaultId, password: 'pass');
      await keys.deleteProfileKey(vaultId);
      // Recreate a legacy password-only entry by configuring then removing its
      // device-local wrap through the storage key used by this service.
      await keys.configureProfile(vaultId: vaultId, password: 'pass');
      await store.delete('security.profile_data_key.v1..admin.$vaultId');
      keys.lockProfile(vaultId);
      expect(
        await keys.verifyProfilePassword(vaultId: vaultId, password: 'pass'),
        isTrue,
      );
      expect(keys.isProfileUnlocked(vaultId), isFalse);
      expect(
        await store.read('security.profile_data_key.v1..admin.$vaultId'),
        isNull,
      );
    },
  );

  test('successful legacy password unlock migrates the admin wrap', () async {
    final store = MemorySecureKeyValueStore();
    final keys = service(store);
    const vaultId = 'private_profile:migrate';
    await keys.configureProfile(vaultId: vaultId, password: 'pass');
    await store.delete('security.profile_data_key.v1..admin.$vaultId');
    keys.lockProfile(vaultId);
    expect(
      await keys.unlockProfile(vaultId: vaultId, password: 'pass'),
      isTrue,
    );
    expect(
      await store.read('security.profile_data_key.v1..admin.$vaultId'),
      isNotNull,
    );
  });

  test(
    'imports preserve matching wraps and invalidate changed payloads',
    () async {
      final sourceStore = MemorySecureKeyValueStore();
      final source = service(sourceStore);
      const vaultId = 'private_profile:import';
      await source.configureProfile(vaultId: vaultId, password: 'pass');
      final exported = await source.exportWrappedProfileKey(vaultId);

      final targetStore = MemorySecureKeyValueStore();
      final target = service(targetStore);
      await target.importWrappedProfileKeys([exported]);
      final before = await targetStore.read(
        'security.profile_data_key.v1..admin.$vaultId',
      );
      expect(before, isNull);
      expect(
        await target.unlockProfile(vaultId: vaultId, password: 'pass'),
        isTrue,
      );
      final adminBefore = await targetStore.read(
        'security.profile_data_key.v1..admin.$vaultId',
      );
      await target.importWrappedProfileKeys([exported], overwrite: true);
      expect(
        await targetStore.read('security.profile_data_key.v1..admin.$vaultId'),
        adminBefore,
      );

      final altered = Map<String, dynamic>.from(exported!)
        ..['salt'] = 'YWx0ZXJlZA==';
      await target.importWrappedProfileKeys([altered], overwrite: true);
      expect(
        await targetStore.read('security.profile_data_key.v1..admin.$vaultId'),
        isNull,
      );
      expect(target.isProfileUnlocked(vaultId), isFalse);
    },
  );

  test('rotation updates admin wrap and deletion removes it', () async {
    final store = MemorySecureKeyValueStore();
    final keys = service(store);
    const vaultId = 'private_profile:rotate';
    await keys.configureProfile(vaultId: vaultId, password: 'old');
    final before = await store.read(
      'security.profile_data_key.v1..admin.$vaultId',
    );
    expect(
      await keys.changeProfilePassword(vaultId: vaultId, newPassword: 'new'),
      isTrue,
    );
    expect(
      await store.read('security.profile_data_key.v1..admin.$vaultId'),
      isNot(before),
    );
    await keys.deleteProfileKey(vaultId);
    expect(
      await store.read('security.profile_data_key.v1..admin.$vaultId'),
      isNull,
    );
  });

  test('locking during password unlock cannot repopulate the key', () async {
    final backing = MemorySecureKeyValueStore();
    final delayed = DelayedProfileReadStore(backing);
    final keys = service(delayed);
    const vaultId = 'private_profile:race';
    await keys.configureProfile(vaultId: vaultId, password: 'pass');
    keys.lockProfile(vaultId);
    delayed.delayNextProfileRead = true;
    final unlocking = keys.unlockProfile(vaultId: vaultId, password: 'pass');
    await delayed.profileReadEntered.future;
    keys.lockProfile(vaultId);
    delayed.releaseProfileRead.complete();
    expect(await unlocking, isFalse);
    expect(keys.isProfileUnlocked(vaultId), isFalse);
  });

  test(
    'changed import during password unlock cannot install the old key',
    () async {
      final backing = MemorySecureKeyValueStore();
      final delayed = DelayedProfileReadStore(backing);
      final keys = service(delayed);
      const vaultId = 'private_profile:race';
      await keys.configureProfile(vaultId: vaultId, password: 'pass');
      final exported = await keys.exportWrappedProfileKey(vaultId);
      final altered = Map<String, dynamic>.from(exported!)
        ..['salt'] = 'YWx0ZXJlZA==';
      keys.lockProfile(vaultId);
      delayed.delayNextProfileRead = true;
      final unlocking = keys.unlockProfile(vaultId: vaultId, password: 'pass');
      await delayed.profileReadEntered.future;
      await keys.importWrappedProfileKeys([altered], overwrite: true);
      delayed.releaseProfileRead.complete();
      expect(await unlocking, isFalse);
      expect(keys.isProfileUnlocked(vaultId), isFalse);
    },
  );

  test('locking during admin restore cannot repopulate the key', () async {
    final backing = MemorySecureKeyValueStore();
    final delayed = DelayedProfileReadStore(backing);
    final keys = service(delayed);
    const vaultId = 'private_profile:race';
    await keys.configureProfile(vaultId: vaultId, password: 'pass');
    keys.lockProfile(vaultId);
    delayed.delayNextAdminRead = true;
    final restoring = keys.unlockProfilesForAdmin([vaultId]);
    await delayed.adminReadEntered.future;
    keys.lockProfile(vaultId);
    delayed.releaseAdminRead.complete();
    expect(await restoring, contains(vaultId));
    expect(keys.isProfileUnlocked(vaultId), isFalse);
  });
}
