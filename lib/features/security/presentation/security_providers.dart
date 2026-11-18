part of '../../home/presentation/home_providers.dart';

final secureKeyValueStoreProvider = Provider<SecureKeyValueStore>((ref) {
  return FlutterSecureKeyValueStore();
});

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

final masterKeyServiceProvider = Provider<MasterKeyService>((ref) {
  final encryption = ref.watch(encryptionServiceProvider);
  return MasterKeyService(
    secureStore: ref.watch(secureKeyValueStoreProvider),
    keyFactory: encryption.generateKeyBytes,
  );
});

final Provider<EncryptedAttachmentStore> encryptedAttachmentStoreProvider =
    Provider<EncryptedAttachmentStore>((ref) {
      final workspace = ref.watch(syncV2WorkspaceProvider);
      final lookup = ref.watch(syncV2AttachmentLookupProvider);
      return SyncV2AttachmentStore(
        encryptionService: ref.watch(encryptionServiceProvider),
        masterKeyService: ref.watch(masterKeyServiceProvider),
        session: () => workspace.noteStoreSession,
        noteStore: () =>
            lookup.store ?? (throw const SyncV2NoteStoreLocked('attachment')),
      );
    });

final deviceIdentityStoreProvider = Provider<DeviceIdentityStore>(
  (ref) => DeviceIdentityStore(),
);
