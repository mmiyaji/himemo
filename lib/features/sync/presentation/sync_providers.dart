part of '../../home/presentation/home_providers.dart';

final secureSyncBundleStoreProvider = Provider<SecureSyncBundleStore>((ref) {
  return SecureSyncBundleStore(
    encryptionService: ref.watch(encryptionServiceProvider),
    syncBundleKeyService: ref.watch(syncBundleKeyServiceProvider),
    legacyMasterKeyService: ref.watch(masterKeyServiceProvider),
    attachmentStore: ref.watch(encryptedAttachmentStoreProvider),
  );
});

final syncBundleKeyServiceForProvider =
    Provider.family<SyncBundleKeyService, SyncProvider>((ref, provider) {
      final usesICloudSharedKey =
          provider == SyncProvider.iCloud &&
          !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS);
      return SyncBundleKeyService(
        secureStore: usesICloudSharedKey
            ? ref.watch(iCloudSynchronizableKeyValueStoreProvider)
            : ref.watch(secureKeyValueStoreProvider),
        fallbackStore: usesICloudSharedKey
            ? ref.watch(secureKeyValueStoreProvider)
            : null,
        keyFactory: ref.watch(encryptionServiceProvider).generateKeyBytes,
      );
    });

final syncBundleKeyServiceProvider = Provider<SyncBundleKeyService>(
  (ref) => ref.watch(
    syncBundleKeyServiceForProvider(ref.watch(syncProviderControllerProvider)),
  ),
);

final syncBundleFingerprintProvider = FutureProvider<String?>((ref) async {
  // Refresh after authenticated key preparation or a transfer creates a key.
  // Observing these states never creates a recovery key itself.
  ref.watch(selectedSyncAuthStateProvider.select((value) => value.stage));
  ref.watch(syncTransferControllerProvider.select((value) => value.stage));
  final fingerprint = await ref
      .watch(syncBundleKeyServiceProvider)
      .existingFullFingerprint();
  return fingerprint?.substring(0, 12);
});

final googleDriveSyncTransportProvider = Provider<GoogleDriveSyncTransport>((
  ref,
) {
  if (_useFakeGoogleDriveSync) {
    return InMemoryGoogleDriveSyncTransport();
  }
  return GoogleApisGoogleDriveSyncTransport(
    authConfig: ref.watch(googleDriveAuthConfigProvider),
  );
});

final googleDriveCloudSyncBundleKeyStoreProvider =
    Provider<GoogleDriveCloudSyncBundleKeyStore>((ref) {
      return GoogleDriveCloudSyncBundleKeyStore(
        ref.watch(googleDriveSyncTransportProvider),
      );
    });

final iCloudSyncTransportProvider = Provider<ICloudSyncTransport>((ref) {
  return MethodChannelICloudSyncTransport();
});

final syncBundleStateStoreProvider = Provider<SyncBundleStateStore>((ref) {
  return SyncBundleStateStore();
});

final syncBundleStateProvider = FutureProvider<SyncBundleState>((ref) async {
  return ref.watch(syncBundleStateStoreProvider).read();
});

final syncConflictWarningProvider = Provider<String?>((ref) {
  final provider = ref.watch(syncProviderControllerProvider);
  final assessment = assessSyncConflict(
    cloudSyncSelected: provider != SyncProvider.off,
    queue: ref.watch(syncQueueSummaryProvider).asData?.value,
    remoteStatus: ref.watch(syncTransferControllerProvider).remoteStatus,
    bundleState: ref.watch(syncBundleStateProvider).asData?.value,
  );
  return assessment.message;
});

final syncQueueSummaryProvider = FutureProvider<SyncQueueSummary>((ref) async {
  return ref.watch(syncEngineProvider).summarizeQueue();
});

final syncHistoryStoreProvider = Provider<SyncHistoryStore>((ref) {
  return SyncHistoryStore();
});

final syncHistoryProvider = FutureProvider<List<SyncHistoryEntry>>((ref) {
  return ref.watch(syncHistoryStoreProvider).read();
});

final syncEngineProvider = Provider<SyncEngine>((ref) {
  return SyncEngine(
    database: ref.watch(encryptedNoteDatabaseProvider),
    attachmentStore: ref.watch(encryptedAttachmentStoreProvider),
    deviceIdentityStore: ref.watch(deviceIdentityStoreProvider),
  );
});
