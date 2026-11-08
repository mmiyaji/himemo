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

final privateProfileSyncExclusionStoreProvider =
    Provider<PrivateProfileSyncExclusionStore>((ref) {
      return PrivateProfileSyncExclusionStore();
    });

/// Vault IDs left out of sync while locked. Sync code reloads the store at
/// each entry point instead of relying on this asynchronously restored view.
final privateProfileSyncExclusionsProvider =
    NotifierProvider<PrivateProfileSyncExclusionsController, Set<String>>(
      PrivateProfileSyncExclusionsController.new,
    );

class PrivateProfileSyncExclusionsController extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    unawaited(load());
    return const <String>{};
  }

  Future<Set<String>> load() async {
    final loaded = await ref
        .read(privateProfileSyncExclusionStoreProvider)
        .read();
    if (ref.mounted) state = loaded;
    return loaded;
  }

  Future<void> setExcluded(String vaultId, bool excluded) async {
    final next = await ref
        .read(privateProfileSyncExclusionStoreProvider)
        .setExcluded(vaultId, excluded);
    if (ref.mounted) state = next;
    ref.invalidate(syncQueueSummaryProvider);
  }
}

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
  final excludedVaultIds = await ref
      .read(privateProfileSyncExclusionStoreProvider)
      .read();
  final profileKeys = ref.read(profileDataKeyServiceProvider);
  return _summarizeSyncQueue(
    ref.watch(syncEngineProvider),
    ref.watch(privateMemoProfileStoreProvider),
    // Excluded locked profiles never upload, so they must not keep automatic
    // sync retrying as if work were pending.
    include: (change) =>
        !excludedVaultIds.contains(change.vaultId) ||
        profileKeys.isProfileUnlocked(change.vaultId),
  );
});

Future<SyncQueueSummary> _summarizeSyncQueue(
  SyncEngine engine,
  PrivateMemoProfileStore profiles, {
  bool Function(PendingNoteChangeRecord change)? include,
}) async {
  final queue = await engine.summarizeQueue(include: include);
  final pendingNames = (await profiles.listProfiles())
      .where((profile) => profile.nameSync.sendableId != null)
      .length;
  if (pendingNames == 0) return queue;
  return SyncQueueSummary(
    totalChanges: queue.totalChanges + pendingNames,
    upserts: queue.upserts + pendingNames,
    deletes: queue.deletes,
    lastQueuedAt: queue.lastQueuedAt,
    profileNameChanges: pendingNames,
  );
}

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
