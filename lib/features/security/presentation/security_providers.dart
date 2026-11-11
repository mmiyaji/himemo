part of '../../home/presentation/home_providers.dart';

final secureKeyValueStoreProvider = Provider<SecureKeyValueStore>((ref) {
  return FlutterSecureKeyValueStore();
});

final iCloudSynchronizableKeyValueStoreProvider = Provider<SecureKeyValueStore>(
  (ref) {
    return FlutterSecureKeyValueStore(
      iOptions: const IOSOptions(
        accountName: 'org.ruhenheim.himemo.cloud_recovery_key',
        synchronizable: true,
        accessibility: KeychainAccessibility.first_unlock,
      ),
      mOptions: const MacOsOptions(
        accountName: 'org.ruhenheim.himemo.cloud_recovery_key',
        synchronizable: true,
      ),
    );
  },
);

final encryptionServiceProvider = Provider<EncryptionService>((ref) {
  return EncryptionService();
});

final appPinLockStoreProvider = Provider<AppPinLockStore>((ref) {
  return AppPinLockStore(
    attemptStore: kIsWeb
        ? PreferencesKeyValueStore()
        : ref.watch(secureKeyValueStoreProvider),
    encryptionService: ref.watch(encryptionServiceProvider),
  );
});

final coverModeSecretStoreProvider = Provider<SecretVerifierStore>((ref) {
  return SecretVerifierStore(
    secureStore: ref.watch(secureKeyValueStoreProvider),
    encryptionService: ref.watch(encryptionServiceProvider),
    storageKey: 'security.cover_mode_secret.v1',
  );
});

final masterKeyServiceProvider = Provider<MasterKeyService>((ref) {
  final encryption = ref.watch(encryptionServiceProvider);
  return MasterKeyService(
    secureStore: ref.watch(secureKeyValueStoreProvider),
    keyFactory: encryption.generateKeyBytes,
  );
});

final encryptedNoteStoreProvider = Provider<EncryptedNoteStore>((ref) {
  return EncryptedNoteStore(
    encryptionService: ref.watch(encryptionServiceProvider),
    masterKeyService: ref.watch(masterKeyServiceProvider),
    profileDataKeyService: ref.watch(profileDataKeyServiceProvider),
    database: ref.watch(encryptedNoteDatabaseProvider),
  );
});

bool get supportsDeviceProfilePin =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android);

final profileDataKeyServiceProvider = Provider<ProfileDataKeyService>((ref) {
  final secureStore = ref.watch(secureKeyValueStoreProvider);
  return ProfileDataKeyService(
    secureStore: secureStore,
    encryptionService: ref.watch(encryptionServiceProvider),
    normalMasterKeyService: ref.watch(masterKeyServiceProvider),
    enableLocalAdminAccess: !kIsWeb,
    devicePinStore: !supportsDeviceProfilePin
        ? null
        : secureStore is FlutterSecureKeyValueStore
        ? FlutterSecureKeyValueStore(
            iOptions: const IOSOptions(
              accountName: 'org.ruhenheim.himemo.device_profile_pin',
              accessibility: KeychainAccessibility.unlocked_this_device,
            ),
          )
        : secureStore,
  );
});

final encryptedNoteDatabaseProvider = Provider<EncryptedNoteDatabase>((ref) {
  final database = EncryptedNoteDatabase();
  ref.onDispose(database.close);
  return database;
});

final deviceIdentityStoreProvider = Provider<DeviceIdentityStore>((ref) {
  return DeviceIdentityStore();
});

final encryptedAttachmentStoreProvider = Provider<EncryptedAttachmentStore>((
  ref,
) {
  return EncryptedAttachmentStore(
    encryptionService: ref.watch(encryptionServiceProvider),
    masterKeyService: ref.watch(masterKeyServiceProvider),
    profileDataKeyService: ref.watch(profileDataKeyServiceProvider),
  );
});

final privateVaultSecretStoreProvider = Provider<PrivateVaultSecretStore>((
  ref,
) {
  return PrivateVaultSecretStore(
    secureStore: ref.watch(secureKeyValueStoreProvider),
    encryptionService: ref.watch(encryptionServiceProvider),
  );
});
