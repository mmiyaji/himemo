part of '../../home/presentation/home_providers.dart';

final syncTransferControllerProvider =
    NotifierProvider<SyncTransferController, SyncTransferState>(
      SyncTransferController.new,
    );

class SyncTransferController extends Notifier<SyncTransferState> {
  static const largeMobileSyncThresholdBytes = 50 * 1024 * 1024;

  // Upload a full snapshot every N delta uploads so remote history can be
  // pruned and devices with an unknown apply anchor can always converge from
  // the newest full bundle.
  static const _fullSnapshotUploadInterval = 20;

  // How many remote bundles to inspect when walking unapplied history.
  static const _remoteBundleWalkHistoryLimit = 50;
  static const _remoteStatusCacheTtl = Duration(seconds: 20);
  static const _iCloudRemoteStatusCacheTtl = Duration(minutes: 2);
  static const _syncBundleDecryptionMessage =
      'sync.error.bundle_decryption_failed';
  static const _syncBundleKeyMissingMessage = 'sync.error.bundle_key_missing';
  static const _iCloudSyncBundleKeyWaitingMessage =
      'sync.error.icloud_keychain_waiting';
  static const _privateProfileNotesPendingUnlockMessage =
      'sync.info.private_profile_notes_pending_unlock';
  static const _downloadedSyncBundleFileName = 'downloaded_sync_bundle.enc';
  static const _pendingPrivateBundleApplyKey =
      'sync.pending_private_bundle_apply.v1';

  // Exact IDs returned by this process's pins avoid a global post-upload scan.
  // Server metadata remains authoritative if the process stops before release.
  final _pinnedAttachmentIds = <String, Set<String>>{};

  Timer? _cooldownTimer;
  Timer? _remoteStatusWaitTimer;
  RemoteSyncBundleStatus? _cachedRemoteStatus;
  DateTime? _cachedRemoteStatusFetchedAt;
  SyncProvider? _cachedRemoteStatusProvider;
  String? _lastFailureSignature;
  int _consecutiveFailureCount = 0;

  @override
  SyncTransferState build() {
    ref.onDispose(() {
      _cooldownTimer?.cancel();
      _remoteStatusWaitTimer?.cancel();
    });
    return const SyncTransferState.idle();
  }

  void _diagnostic(
    String message, {
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    logDiagnostic('sync', message, data: data);
  }

  void clearLocalBundleCache() {
    state = state.copyWith(clearLocalBundle: true);
  }

  void clearRetryCooldown() {
    _cooldownTimer?.cancel();
    state = state.copyWith(clearCooldown: true);
    _diagnostic('sync retry cooldown cleared');
  }

  Future<SyncQueueSummary> _readLocalSyncQueueSummary() {
    return ref.read(syncEngineProvider).summarizeQueue();
  }

  Future<void> _recordSyncHistory({
    required DateTime startedAt,
    required String operation,
    required bool success,
    String? message,
    SyncQueueSummary? queueBefore,
    SyncQueueSummary? queueAfter,
    RemoteSyncBundleStatus? remoteStatus,
    StoredSyncBundle? localBundle,
  }) async {
    final provider = ref.read(syncProviderControllerProvider);
    final noteCount = remoteStatus?.noteCount ?? localBundle?.noteCount;
    final attachmentCount =
        remoteStatus?.attachmentCount ?? localBundle?.attachmentCount;
    await ref
        .read(syncHistoryStoreProvider)
        .add(
          SyncHistoryEntry(
            startedAt: startedAt,
            finishedAt: DateTime.now(),
            provider: provider,
            operation: operation,
            success: success,
            message: message,
            noteCount: noteCount,
            attachmentCount: attachmentCount,
            queueBefore: queueBefore,
            queueAfter: queueAfter,
          ),
        );
    ref.invalidate(syncHistoryProvider);
    if (success) {
      _lastFailureSignature = null;
      _consecutiveFailureCount = 0;
      return;
    }
    _applyFailureBackoff(operation: operation, message: message);
  }

  void _applyFailureBackoff({required String operation, String? message}) {
    final signature = '$operation:${message ?? ''}';
    if (_lastFailureSignature == signature) {
      _consecutiveFailureCount += 1;
    } else {
      _lastFailureSignature = signature;
      _consecutiveFailureCount = 1;
    }
    final retryAfter = switch (_consecutiveFailureCount) {
      1 => Duration.zero,
      2 => const Duration(seconds: 20),
      3 => const Duration(minutes: 1),
      _ => const Duration(minutes: 5),
    };
    if (retryAfter == Duration.zero) {
      return;
    }
    _scheduleCooldownRefresh(retryAfter);
    state = state.copyWith(cooldownUntil: DateTime.now().add(retryAfter));
    _diagnostic(
      'sync retry cooldown scheduled',
      data: {
        'operation': operation,
        'failures': _consecutiveFailureCount,
        'retryAfterSeconds': retryAfter.inSeconds,
      },
    );
  }

  Future<LargeSyncTransferWarning?> largeMobileTransferWarning({
    bool includeUpload = true,
    bool includeDownload = true,
    bool estimateAllLocalNotes = false,
    int? downloadBytesOverride,
  }) async {
    final kind = await ref.read(networkConnectionServiceProvider).currentKind();
    if (kind != NetworkConnectionKind.mobile) {
      return null;
    }
    if (includeDownload &&
        downloadBytesOverride != null &&
        downloadBytesOverride >= largeMobileSyncThresholdBytes) {
      return LargeSyncTransferWarning(
        direction: LargeSyncTransferDirection.download,
        bytes: downloadBytesOverride,
        thresholdBytes: largeMobileSyncThresholdBytes,
      );
    }
    if (includeDownload && downloadBytesOverride == null) {
      var remoteStatus = state.remoteStatus;
      if (remoteStatus == null &&
          _supportsRemoteTransport(ref.read(syncProviderControllerProvider))) {
        final bundleState = await ref.read(syncBundleStateProvider.future);
        if (bundleState.lastRemoteFileId != null &&
            bundleState.lastRemoteFileId!.isNotEmpty) {
          remoteStatus = RemoteSyncBundleStatus(
            fileId: bundleState.lastRemoteFileId!,
            fileName: '',
            modifiedAt: bundleState.lastRemoteModifiedAt,
            deviceId: bundleState.lastRemoteDeviceId,
          );
          state = state.copyWith(remoteStatus: remoteStatus);
        }
        unawaited(_refreshRemoteStatusInBackground());
      }
      final remoteSize = remoteStatus?.sizeBytes;
      final bundleState = await ref.read(syncBundleStateProvider.future);
      final needsDownload =
          remoteStatus != null &&
          remoteBundleNeedsApplyForSync(remoteStatus, bundleState);
      if (needsDownload &&
          remoteSize != null &&
          remoteSize >= largeMobileSyncThresholdBytes) {
        return LargeSyncTransferWarning(
          direction: LargeSyncTransferDirection.download,
          bytes: remoteSize,
          thresholdBytes: largeMobileSyncThresholdBytes,
        );
      }
    }
    if (!includeUpload) {
      return null;
    }
    final uploadBytes = estimateAllLocalNotes
        ? await estimateCurrentStateUploadBytes()
        : await estimatePendingUploadBytes();
    if (uploadBytes >= largeMobileSyncThresholdBytes) {
      return LargeSyncTransferWarning(
        direction: LargeSyncTransferDirection.upload,
        bytes: uploadBytes,
        thresholdBytes: largeMobileSyncThresholdBytes,
      );
    }
    return null;
  }

  Future<int> estimatePendingUploadBytes() async {
    final pendingChanges = await ref
        .read(syncEngineProvider)
        .loadPendingChanges();
    final pendingIds = pendingChanges.map((change) => change.noteId).toSet();
    final notes = await ref
        .read(notesControllerProvider.notifier)
        .notesForSyncSnapshot(pendingNoteIds: pendingIds);
    return ref.read(syncEngineProvider).estimateNotesPayloadBytes(notes);
  }

  Future<int> estimateCurrentStateUploadBytes() async {
    final syncExclusionTags = ref.read(syncExclusionTagsControllerProvider);
    final notes = ref
        .read(notesControllerProvider)
        .where(
          (note) =>
              !isGeneratedSampleNote(note) &&
              (!isPrivateVaultId(note.vaultId) ||
                  ref
                      .read(profileDataKeyServiceProvider)
                      .isProfileUnlocked(note.vaultId)) &&
              !noteExcludedFromSync(note, syncExclusionTags),
        )
        .map((note) {
          final syncState = note.deletedAt == null
              ? NoteSyncState.pendingUpload
              : NoteSyncState.pendingDelete;
          return note.copyWith(syncState: syncState);
        })
        .toList(growable: false);
    return ref.read(syncEngineProvider).estimateNotesPayloadBytes(notes);
  }

  Future<bool> _shouldBlockLargeMobileTransfer({
    required bool allowLargeMobileTransfer,
    required bool silentLargeMobileSkip,
    bool includeUpload = true,
    bool includeDownload = true,
    bool estimateAllLocalNotes = false,
    int? downloadBytesOverride,
  }) async {
    if (allowLargeMobileTransfer) {
      return false;
    }
    final warning = await largeMobileTransferWarning(
      includeUpload: includeUpload,
      includeDownload: includeDownload,
      estimateAllLocalNotes: estimateAllLocalNotes,
      downloadBytesOverride: downloadBytesOverride,
    );
    if (warning == null) {
      return false;
    }
    _diagnostic(
      'large mobile sync blocked',
      data: {
        'direction': warning.direction.name,
        'bytes': warning.bytes,
        'thresholdBytes': warning.thresholdBytes,
        'silent': silentLargeMobileSkip,
      },
    );
    if (!silentLargeMobileSkip) {
      state = const SyncTransferState(
        stage: SyncTransferStage.error,
        message: 'sync.error.large_mobile_transfer_requires_confirmation',
      );
    } else if (state.stage == SyncTransferStage.busy) {
      state = SyncTransferState(
        stage: SyncTransferStage.idle,
        remoteStatus: state.remoteStatus,
        localBundle: state.localBundle,
      );
    }
    return true;
  }

  void _startBusy(SyncTransferProgress progress) {
    state = state.copyWith(
      stage: SyncTransferStage.busy,
      progress: progress,
      clearMessage: true,
      clearDetail: true,
      clearCooldown: true,
    );
  }

  void _setProgress(SyncTransferProgress progress) {
    state = state.copyWith(
      stage: SyncTransferStage.busy,
      progress: progress,
      clearMessage: true,
    );
  }

  void _setProgressDetail({
    required SyncTransferProgress progress,
    String? detail,
    int? completedItems,
    int? totalItems,
  }) {
    state = state.copyWith(
      stage: SyncTransferStage.busy,
      progress: progress,
      detail: detail,
      completedItems: completedItems,
      totalItems: totalItems,
      clearMessage: true,
      clearDetail:
          detail == null && completedItems == null && totalItems == null,
    );
  }

  DateTime _lastUiYieldAt = DateTime.fromMillisecondsSinceEpoch(0);

  // Yields to the event loop at most every few milliseconds. Sync loops call
  // this once per note/attachment; an unthrottled timer hop per item adds
  // seconds of pure scheduling overhead on large libraries.
  Future<void> _yieldToUi() {
    final now = DateTime.now();
    if (now.difference(_lastUiYieldAt) < const Duration(milliseconds: 8)) {
      return Future<void>.value();
    }
    _lastUiYieldAt = now;
    return Future<void>.delayed(Duration.zero);
  }

  Future<T> _measureSyncStep<T>(
    String message,
    Future<T> Function() operation, {
    Map<String, Object?> data = const <String, Object?>{},
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      return await operation();
    } finally {
      stopwatch.stop();
      _diagnostic(
        message,
        data: {...data, 'elapsedMs': stopwatch.elapsedMilliseconds},
      );
    }
  }

  bool _canUseCachedRemoteStatus(SyncProvider provider) {
    final fetchedAt = _cachedRemoteStatusFetchedAt;
    final ttl = provider == SyncProvider.iCloud
        ? _iCloudRemoteStatusCacheTtl
        : _remoteStatusCacheTtl;
    return fetchedAt != null &&
        _cachedRemoteStatusProvider == provider &&
        DateTime.now().difference(fetchedAt) < ttl;
  }

  void _cacheRemoteStatus(
    SyncProvider provider,
    RemoteSyncBundleStatus? remoteStatus,
  ) {
    _cachedRemoteStatusProvider = provider;
    _cachedRemoteStatusFetchedAt = DateTime.now();
    _cachedRemoteStatus = remoteStatus;
  }

  void _startRemoteStatusWaitProgress({
    required SyncProvider provider,
    required int totalItems,
  }) {
    _remoteStatusWaitTimer?.cancel();
    final startedAt = DateTime.now();

    void update() {
      final elapsed = DateTime.now().difference(startedAt).inSeconds;
      _setProgressDetail(
        progress: SyncTransferProgress.checkingRemote,
        detail: _remoteStatusWaitDetail(provider, elapsed),
        completedItems: 0,
        totalItems: totalItems,
      );
    }

    update();
    _remoteStatusWaitTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => update(),
    );
  }

  String _remoteStatusWaitDetail(SyncProvider provider, int elapsedSeconds) {
    final providerName = switch (provider) {
      SyncProvider.iCloud => 'iCloud',
      SyncProvider.googleDrive => 'Google Drive',
      SyncProvider.off => 'cloud',
    };
    final elapsedSuffix = elapsedSeconds <= 0 ? '' : ' (${elapsedSeconds}s)';
    if (provider == SyncProvider.iCloud && elapsedSeconds >= 10) {
      return 'Still waiting for iCloud metadata$elapsedSuffix';
    }
    if (provider == SyncProvider.iCloud && elapsedSeconds >= 5) {
      return 'iCloud is taking longer than usual$elapsedSuffix';
    }
    return 'Requesting latest $providerName metadata$elapsedSuffix';
  }

  Future<RemoteSyncBundleStatus?> _fetchLatestRemoteStatusWithCache({
    required String traceName,
    required bool allowCached,
    required int totalItems,
  }) async {
    final provider = ref.read(syncProviderControllerProvider);
    if (allowCached && _canUseCachedRemoteStatus(provider)) {
      _diagnostic(
        'remote status cache hit',
        data: {
          'provider': provider.name,
          'ageMs': DateTime.now()
              .difference(_cachedRemoteStatusFetchedAt!)
              .inMilliseconds,
          'hasRemote': _cachedRemoteStatus != null,
          'fileId': _cachedRemoteStatus?.fileId,
        },
      );
      _setProgressDetail(
        progress: SyncTransferProgress.checkingRemote,
        detail: 'Using recent cloud status',
        completedItems: 1,
        totalItems: totalItems,
      );
      await _yieldToUi();
      return _cachedRemoteStatus;
    }
    _startRemoteStatusWaitProgress(provider: provider, totalItems: totalItems);
    try {
      final remoteStatus = await runFirebaseTrace(
        traceName,
        _fetchLatestRemoteStatus,
      );
      _cacheRemoteStatus(provider, remoteStatus);
      return remoteStatus;
    } finally {
      _remoteStatusWaitTimer?.cancel();
      _remoteStatusWaitTimer = null;
    }
  }

  Future<void> refreshRemoteStatus({
    bool allowCachedRemoteStatus = false,
  }) async {
    final provider = ref.read(syncProviderControllerProvider);
    if (!_supportsRemoteTransport(provider)) {
      state = const SyncTransferState(
        stage: SyncTransferStage.idle,
        message: 'sync.info.select_target_for_remote_status',
      );
      return;
    }
    _startBusy(SyncTransferProgress.checkingRemote);
    await _yieldToUi();
    try {
      _setProgressDetail(
        progress: SyncTransferProgress.checkingRemote,
        detail: 'Checking cloud status',
        completedItems: 0,
        totalItems: 1,
      );
      await _yieldToUi();
      var remoteStatus = await _measureSyncStep(
        'remote status check completed',
        () => _fetchLatestRemoteStatusWithCache(
          traceName: 'sync_refresh_remote_status',
          allowCached: allowCachedRemoteStatus,
          totalItems: 1,
        ),
        data: {'cachedAllowed': allowCachedRemoteStatus},
      );
      state = SyncTransferState(
        stage: SyncTransferStage.success,
        message: remoteStatus == null
            ? 'sync.info.no_remote_bundle'
            : 'sync.info.remote_bundle_refreshed',
        remoteStatus: remoteStatus,
        localBundle: state.localBundle,
      );
      if (remoteStatus != null) {
        await ref
            .read(syncBundleStateStoreProvider)
            .recordRemoteStatus(remoteStatus);
      }
    } catch (error) {
      state = _failureState(error, remoteStatus: state.remoteStatus);
    }
  }

  Future<ICloudStorageBreakdown> fetchICloudStorageBreakdown() async {
    final provider = ref.read(syncProviderControllerProvider);
    if (provider != SyncProvider.iCloud) {
      throw StateError('iCloud sync is not selected.');
    }
    _diagnostic('icloud storage breakdown requested');
    final breakdown = await runFirebaseTrace(
      'sync_icloud_storage_breakdown',
      () => ref.read(iCloudSyncTransportProvider).fetchStorageBreakdown(),
    );
    _diagnostic(
      'icloud storage breakdown loaded',
      data: {
        'bundleCount': breakdown.bundleCount,
        'bundleBytes': breakdown.bundleBytes,
        'attachmentCount': breakdown.attachmentCount,
        'attachmentBytes': breakdown.attachmentBytes,
        'totalBytes': breakdown.totalBytes,
      },
    );
    return breakdown;
  }

  Future<ICloudMaintenanceResult> compactICloudStorage({
    int keepLatest = 1,
  }) async {
    final provider = ref.read(syncProviderControllerProvider);
    if (provider != SyncProvider.iCloud) {
      throw StateError('iCloud sync is not selected.');
    }
    _diagnostic(
      'icloud storage compact requested',
      data: {'keepLatest': keepLatest},
    );
    final lockedPrivateUpsertIds = await _lockedPrivateUpsertSnapshotIds();
    if (lockedPrivateUpsertIds.isNotEmpty) {
      _diagnostic(
        'icloud storage compact blocked by locked private profiles',
        data: {'lockedPrivateUpserts': lockedPrivateUpsertIds.length},
      );
      throw StateError('sync.error.unlock_private_profiles_before_compact');
    }
    await uploadCurrentBundle(
      force: true,
      fullSnapshot: true,
      pruneAfterUpload: false,
    );
    final published = state.remoteStatus;
    if (state.stage != SyncTransferStage.success ||
        published == null ||
        !published.isFullBundle) {
      throw StateError(
        state.message ?? 'sync.error.local_bundle_prepare_failed',
      );
    }
    final result = await _safePruneRemoteHistory(
      published,
      keepLatest: keepLatest,
    );
    final referencedHashes = <String>{};
    _diagnostic(
      'icloud storage compact completed',
      data: {
        'deletedBundleCount': result.deletedBundleCount,
        'deletedBundleBytes': result.deletedBundleBytes,
        'deletedAttachmentCount': result.deletedAttachmentCount,
        'deletedAttachmentBytes': result.deletedAttachmentBytes,
        'referencedAttachmentHashes': referencedHashes.length,
      },
    );
    await refreshRemoteStatus();
    return result;
  }

  Future<Set<String>> _lockedPrivateUpsertSnapshotIds() async {
    final lockedIds = <String>{};
    final profileKeys = ref.read(profileDataKeyServiceProvider);
    final snapshots = await ref.read(encryptedNoteDatabaseProvider).loadAll();
    for (final snapshot in snapshots) {
      final note = snapshot.note;
      if (!isPrivateVaultId(note.vaultId) || note.deletedAt != null) {
        continue;
      }
      final key = await profileKeys.keyForVault(note.vaultId);
      if (key == null) {
        lockedIds.add(note.id);
      }
    }
    return lockedIds;
  }

  Future<void> uploadCurrentBundle({
    bool force = false,
    bool fullSnapshot = false,
    bool deltaOnly = false,
    String? expectedRemoteFileId,
    Set<String>? onlyPendingNoteIds,
    bool allowLargeMobileTransfer = false,
    bool silentLargeMobileSkip = false,
    bool pruneAfterUpload = true,
  }) async {
    final historyStartedAt = DateTime.now();
    var recoveringFullHistory = false;
    final uploadId = base64Url
        .encode(
          List<int>.generate(16, (_) => math.Random.secure().nextInt(256)),
        )
        .replaceAll('=', '');
    final provider = ref.read(syncProviderControllerProvider);
    _diagnostic(
      'upload requested',
      data: {
        'provider': provider.name,
        'force': force,
        'deltaOnly': deltaOnly,
        'expectedRemoteFileId': expectedRemoteFileId,
        'pendingNoteFilterCount': onlyPendingNoteIds?.length,
      },
    );
    if (!_supportsRemoteTransport(provider)) {
      _diagnostic(
        'upload skipped unsupported provider',
        data: {'provider': provider.name},
      );
      state = const SyncTransferState(
        stage: SyncTransferStage.error,
        message: 'sync.error.select_target_for_upload',
      );
      await _recordSyncHistory(
        startedAt: historyStartedAt,
        operation: 'upload',
        success: false,
        message: state.message,
      );
      return;
    }
    if (expectedRemoteFileId == null) {
      try {
        final preparation = await _applyRemoteBeforeUpload(
          allowIncompleteHistory: force && fullSnapshot,
          allowLargeMobileTransfer: allowLargeMobileTransfer,
          silentLargeMobileSkip: silentLargeMobileSkip,
        );
        if (!preparation.ready) return;
        recoveringFullHistory = preparation.recoveringFullHistory;
      } catch (error) {
        state = _failureState(error);
        return;
      }
    }
    if (expectedRemoteFileId == null &&
        ref
            .read(notesControllerProvider)
            .any((note) => note.syncState == NoteSyncState.conflict)) {
      state = state.copyWith(
        stage: SyncTransferStage.error,
        message: 'sync.error.conflict_review_remote',
      );
      return;
    }
    final queueBeforeUpload = await _readLocalSyncQueueSummary();
    final assessment = assessSyncConflict(
      cloudSyncSelected: true,
      queue: queueBeforeUpload,
      remoteStatus: state.remoteStatus,
      bundleState: await ref.read(syncBundleStateStoreProvider).read(),
    );
    final reviewedRemoteStillSelected =
        expectedRemoteFileId != null &&
        state.remoteStatus?.fileId == expectedRemoteFileId;
    if (expectedRemoteFileId != null && !reviewedRemoteStillSelected) {
      _diagnostic(
        'upload blocked because reviewed remote anchor changed',
        data: {
          'expectedRemoteFileId': expectedRemoteFileId,
          'currentRemoteFileId': state.remoteStatus?.fileId,
        },
      );
      state = state.copyWith(
        stage: SyncTransferStage.error,
        message: 'sync.error.conflict_remote_changed_after_review',
      );
      await _recordSyncHistory(
        startedAt: historyStartedAt,
        operation: 'upload',
        success: false,
        message: state.message,
        queueBefore: queueBeforeUpload,
      );
      return;
    }
    if (assessment.hasConflict && !force && !reviewedRemoteStillSelected) {
      _diagnostic(
        'upload conflict detected',
        data: {'message': assessment.message},
      );
      state = state.copyWith(
        stage: SyncTransferStage.error,
        message: 'sync.error.conflict_download_first_or_force_upload',
      );
      await _recordSyncHistory(
        startedAt: historyStartedAt,
        operation: 'upload',
        success: false,
        message: state.message,
        queueBefore: queueBeforeUpload,
      );
      return;
    }
    if (await _shouldBlockLargeMobileTransfer(
      allowLargeMobileTransfer: allowLargeMobileTransfer,
      silentLargeMobileSkip: silentLargeMobileSkip,
      includeDownload: false,
    )) {
      return;
    }
    _startBusy(SyncTransferProgress.preparingBundle);
    await _yieldToUi();
    try {
      if (_managedAttachmentTransport() != null) {
        await _recoverAttachmentReservations();
        _pinnedAttachmentIds.clear();
        await _uploadReservations().start(uploadId);
      }
      await logFirebaseBreadcrumb('sync upload requested');
      final bundleStateBeforeUpload = await ref
          .read(syncBundleStateStoreProvider)
          .read();
      // Delta sync: regular uploads carry only the queued changes. A full
      // snapshot (all syncable notes) is uploaded on the first upload, every
      // _fullSnapshotUploadInterval delta uploads, or when explicitly
      // requested (force upload / re-upload / storage compaction).
      final uploadFullSnapshot =
          expectedRemoteFileId == null &&
          onlyPendingNoteIds == null &&
          !deltaOnly &&
          (fullSnapshot ||
              bundleStateBeforeUpload.lastFullUploadedAt == null ||
              bundleStateBeforeUpload.deltaUploadsSinceFull >=
                  _fullSnapshotUploadInterval);
      _diagnostic(
        'upload mode selected',
        data: {
          'fullSnapshot': uploadFullSnapshot,
          'deltaUploadsSinceFull':
              bundleStateBeforeUpload.deltaUploadsSinceFull,
        },
      );
      if (uploadFullSnapshot) {
        await ref
            .read(notesControllerProvider.notifier)
            .queueCurrentStateForSync();
      }
      var pendingChanges = await ref
          .read(syncEngineProvider)
          .loadPendingChanges();
      if (onlyPendingNoteIds != null) {
        pendingChanges = pendingChanges
            .where((change) => onlyPendingNoteIds.contains(change.noteId))
            .toList(growable: false);
      }
      if (pendingChanges.isEmpty) {
        final queuedAt = DateTime.now();
        pendingChanges = [
          for (final note in ref.read(notesControllerProvider))
            if (note.syncState == NoteSyncState.pendingUpload ||
                note.syncState == NoteSyncState.pendingDelete)
              if (onlyPendingNoteIds == null ||
                  onlyPendingNoteIds.contains(note.id))
                PendingNoteChangeRecord(
                  noteId: note.id,
                  vaultId: note.vaultId,
                  revision: note.revision,
                  action: note.syncState == NoteSyncState.pendingDelete
                      ? PendingNoteChangeAction.delete
                      : PendingNoteChangeAction.upsert,
                  queuedAt: note.updatedAt ?? queuedAt,
                  contentHash: note.contentHash,
                  deletedAt: note.deletedAt,
                ),
        ];
      }
      // Resolve the target's attachment objects before preparing either public
      // or private snapshots.  Cached hashes can only be reused when the
      // selected target still contains their object.
      final provider = ref.read(syncProviderControllerProvider);
      final remoteAttachmentContentHashes = provider == SyncProvider.off
          ? null
          : await _listExistingRemoteAttachmentHashes();
      final privateSyncPayload = await _preparePrivateSyncNotes(
        pendingChanges,
        includeAllPrivateSnapshots: uploadFullSnapshot,
        remoteAttachmentContentHashes: remoteAttachmentContentHashes,
      );
      final encryptedPrivateNotes = privateSyncPayload.notes;
      final encryptedPrivateNoteIds = {
        for (final entry in encryptedPrivateNotes) entry.note.id,
      };
      final skippedLockedPrivateUpsertIds =
          privateSyncPayload.skippedLockedUpsertIds;
      if (skippedLockedPrivateUpsertIds.isNotEmpty) {
        _diagnostic(
          'locked private profile upserts skipped for upload',
          data: {'count': skippedLockedPrivateUpsertIds.length},
        );
        if (fullSnapshot) {
          // An explicitly requested full re-upload must not silently become
          // an incomplete delta. Routine sync can safely keep its existing
          // delta behavior until every private profile is unlocked.
          throw const SyncSafetyException(
            'sync.error.unlock_private_profiles_before_full_upload',
          );
        }
        pendingChanges = pendingChanges
            .where(
              (change) =>
                  !skippedLockedPrivateUpsertIds.contains(change.noteId),
            )
            .toList(growable: false);
      }
      if (encryptedPrivateNoteIds.isNotEmpty) {
        _diagnostic(
          'private profile notes prepared encrypted',
          data: {'count': encryptedPrivateNoteIds.length},
        );
        pendingChanges = pendingChanges
            .where((change) => !encryptedPrivateNoteIds.contains(change.noteId))
            .toList(growable: false);
      }
      final uploadBundleKind =
          uploadFullSnapshot && skippedLockedPrivateUpsertIds.isEmpty
          ? SyncBundleKind.full
          : SyncBundleKind.delta;
      final uploadAdvertisesFullSnapshot =
          uploadBundleKind == SyncBundleKind.full;
      if (uploadFullSnapshot && !uploadAdvertisesFullSnapshot) {
        _diagnostic(
          'full snapshot advertised as delta because locked private upserts were skipped',
          data: {'lockedPrivateUpserts': skippedLockedPrivateUpsertIds.length},
        );
      }
      final pendingIds = pendingChanges.map((change) => change.noteId).toSet();
      final notes = await ref
          .read(notesControllerProvider.notifier)
          .notesForSyncSnapshot(pendingNoteIds: pendingIds);
      final uploadableNoteIds = notes.map((note) => note.id).toSet();
      final syncExclusionTags = ref.read(syncExclusionTagsControllerProvider);
      final currentNotesById = {
        for (final note in ref.read(notesControllerProvider)) note.id: note,
      };
      final excludedPendingIds = pendingChanges
          .where((change) {
            if (uploadableNoteIds.contains(change.noteId)) {
              return false;
            }
            final note = currentNotesById[change.noteId];
            return note != null &&
                noteExcludedFromSync(note, syncExclusionTags);
          })
          .map((change) => change.noteId)
          .toSet();
      // Pending upserts whose note is not uploadable fall into three buckets:
      // excluded by sync tags (safe to prune), gone from both memory and the
      // encrypted database (safe to prune), or present somewhere but not
      // uploadable right now (must NOT be pruned — pruning would silently
      // drop a change that was never uploaded).
      final unresolvedUpsertIds = pendingChanges
          .where(
            (change) =>
                change.action == PendingNoteChangeAction.upsert &&
                !uploadableNoteIds.contains(change.noteId) &&
                !excludedPendingIds.contains(change.noteId),
          )
          .map((change) => change.noteId)
          .toSet();
      final missingEverywhereIds = <String>{};
      if (unresolvedUpsertIds.isNotEmpty) {
        final idsInDatabase = await ref
            .read(encryptedNoteDatabaseProvider)
            .existingNoteIds(unresolvedUpsertIds);
        for (final noteId in unresolvedUpsertIds) {
          if (!currentNotesById.containsKey(noteId) &&
              !idsInDatabase.contains(noteId)) {
            missingEverywhereIds.add(noteId);
          }
        }
        final blockedCount =
            unresolvedUpsertIds.length - missingEverywhereIds.length;
        if (blockedCount > 0) {
          _diagnostic(
            'pending changes kept for notes not currently uploadable',
            data: {'count': blockedCount},
          );
        }
      }
      final stalePendingChangeIds = {
        ...excludedPendingIds,
        ...missingEverywhereIds,
      };
      if (stalePendingChangeIds.isNotEmpty) {
        _diagnostic(
          'stale pending changes pruned before upload',
          data: {
            'count': stalePendingChangeIds.length,
            'excluded': excludedPendingIds.length,
            'missingEverywhere': missingEverywhereIds.length,
          },
        );
        await ref
            .read(encryptedNoteDatabaseProvider)
            .deletePendingChangesByIds(stalePendingChangeIds);
        pendingChanges = pendingChanges
            .where((change) => !stalePendingChangeIds.contains(change.noteId))
            .toList(growable: false);
      }
      if (pendingChanges.isEmpty && encryptedPrivateNotes.isEmpty) {
        ref.invalidate(syncQueueSummaryProvider);
        final queueAfterUpload = await _readLocalSyncQueueSummary();
        _diagnostic(
          'upload skipped no uploadable changes',
          data: {
            'queueChanges': queueAfterUpload.totalChanges,
            'queueUpserts': queueAfterUpload.upserts,
            'queueDeletes': queueAfterUpload.deletes,
          },
        );
        state = SyncTransferState(
          stage: SyncTransferStage.success,
          message: 'sync.info.no_changes_to_upload',
          remoteStatus: state.remoteStatus,
          localBundle: state.localBundle,
        );
        await _recordSyncHistory(
          startedAt: historyStartedAt,
          operation: 'upload',
          success: true,
          message: state.message,
          queueBefore: queueBeforeUpload,
          queueAfter: queueAfterUpload,
        );
        return;
      }
      final publicPendingHashes = {
        for (final change in pendingChanges) change.noteId: change.contentHash,
      };
      final snapshot = await runFirebaseTrace(
        'sync_prepare_snapshot',
        () => ref
            .read(syncEngineProvider)
            .prepareSnapshot(
              notes,
              pendingChanges: pendingChanges,
              managedAttachmentReferences:
                  _managedAttachmentTransport() != null,
              remoteAttachmentContentHashes: remoteAttachmentContentHashes,
              verifyRemoteAttachmentObjects:
                  provider != SyncProvider.off &&
                  remoteAttachmentContentHashes == null,
              onProgress: (progress) async {
                _setProgressDetail(
                  progress: SyncTransferProgress.preparingBundle,
                  detail: progress.detail,
                  completedItems: progress.completedItems,
                  totalItems: progress.totalItems,
                );
                await _yieldToUi();
              },
            ),
      );
      final preparedUpserts = snapshot.notes
          .where((change) => change.action == PendingNoteChangeAction.upsert)
          .length;
      if (preparedUpserts < snapshot.summary.upserts) {
        throw StateError('sync.error.local_snapshot_incomplete');
      }
      _diagnostic(
        'snapshot prepared',
        data: {
          'changes': snapshot.summary.totalChanges,
          'upserts': snapshot.summary.upserts,
          'deletes': snapshot.summary.deletes,
          'preparedNotes': snapshot.notes.length,
          'attachments': snapshot.attachments.length,
        },
      );
      final uploadSnapshot = privateSyncPayload.attachments.isEmpty
          ? snapshot
          : PreparedSyncSnapshot(
              deviceId: snapshot.deviceId,
              exportedAt: snapshot.exportedAt,
              summary: snapshot.summary,
              notes: snapshot.notes,
              attachments: [
                ...snapshot.attachments,
                ...privateSyncPayload.attachments,
              ],
            );
      if (privateSyncPayload.attachments.isNotEmpty) {
        _diagnostic(
          'private profile attachment objects prepared',
          data: {'count': privateSyncPayload.attachments.length},
        );
      }
      final privateProfiles = await ref
          .read(privateMemoProfileStoreProvider)
          .exportSyncPayload();
      if (provider != SyncProvider.off) {
        _setProgress(SyncTransferProgress.uploadingBundle);
        await _yieldToUi();
        await runFirebaseTrace(
          'sync_upload_attachment_objects',
          () => _uploadRemoteAttachmentObjects(
            uploadSnapshot.attachments,
            uploadId: uploadId,
            referencedHashes: {
              for (final entry in uploadSnapshot.notes)
                ...syncAttachmentObjectHashesInNoteJson(entry.note.toJson()),
            },
          ),
        );
      }
      final exclusionRetention = uploadAdvertisesFullSnapshot
          ? await _prepareExclusionRetention()
          : null;
      final coverageHistory = uploadAdvertisesFullSnapshot
          ? await _listReplayHistory(const SyncBundleState())
          : const <RemoteSyncBundleStatus>[];
      final exactApplied =
          (await ref.read(syncBundleStateStoreProvider).read())
              .appliedRemoteFileIds ??
          const <String>{};
      final coverage = uploadAdvertisesFullSnapshot
          ? SyncBundleCoverage(
              coveredBundleIds: exactApplied.intersection(
                coverageHistory.map((item) => item.fileId).toSet(),
              ),
            )
          : null;
      final uploadReceipts = uploadAdvertisesFullSnapshot
          ? await _publishedUploadReceipts(coverageHistory)
          : const <String, String>{};
      final bundle = await runFirebaseTrace(
        'sync_write_local_bundle',
        () => ref
            .read(secureSyncBundleStoreProvider)
            .writeBundle(
              uploadSnapshot,
              privateProfiles: [privateProfiles],
              encryptedPrivateNotes: encryptedPrivateNotes,
              inlineAttachments: provider == SyncProvider.off,
              bundleKind: uploadBundleKind,
              exclusionRetention: exclusionRetention,
              coverage: coverage,
              uploadId: uploadId,
              uploadReceipts: uploadReceipts,
            ),
      );
      final encodedPayload = await runFirebaseTrace(
        'sync_read_local_bundle_payload',
        () => ref
            .read(secureSyncBundleStoreProvider)
            .readEncryptedBundlePayload(bundle.reference),
      );
      if (encodedPayload == null || encodedPayload.isEmpty) {
        throw StateError('sync.error.local_bundle_prepare_failed');
      }
      _diagnostic(
        'local bundle prepared',
        data: {
          'notes': bundle.noteCount,
          'attachments': bundle.attachmentCount,
          'payloadLength': encodedPayload.length,
        },
      );
      // Re-check the remote right before publishing the bundle. Preparation
      // and attachment uploads can take a while; another device may have
      // uploaded in the meantime, and overwriting the "latest" pointer
      // without applying it first would hide that device's changes.
      if (provider != SyncProvider.off) {
        final freshRemoteStatus = await runFirebaseTrace(
          'sync_preupload_remote_recheck',
          _fetchLatestRemoteStatus,
        );
        if (expectedRemoteFileId != null &&
            freshRemoteStatus?.fileId != expectedRemoteFileId) {
          if (freshRemoteStatus != null) {
            _cacheRemoteStatus(provider, freshRemoteStatus);
          }
          _diagnostic(
            'upload aborted because reviewed remote anchor changed',
            data: {
              'expectedRemoteFileId': expectedRemoteFileId,
              'freshRemoteFileId': freshRemoteStatus?.fileId,
            },
          );
          state = state.copyWith(
            stage: SyncTransferStage.error,
            message: 'sync.error.conflict_remote_changed_after_review',
            remoteStatus: freshRemoteStatus ?? state.remoteStatus,
          );
          await _recordSyncHistory(
            startedAt: historyStartedAt,
            operation: 'upload',
            success: false,
            message: state.message,
            queueBefore: queueBeforeUpload,
            remoteStatus: freshRemoteStatus ?? state.remoteStatus,
            localBundle: bundle,
          );
          return;
        }
        if (freshRemoteStatus != null) {
          _cacheRemoteStatus(provider, freshRemoteStatus);
          final latestBundleState = await ref
              .read(syncBundleStateStoreProvider)
              .read();
          if (expectedRemoteFileId == null &&
              _remoteBundleNeedsApply(freshRemoteStatus, latestBundleState)) {
            _diagnostic(
              'upload aborted remote bundle changed during preparation',
              data: {
                'remoteFileId': freshRemoteStatus.fileId,
                'remoteModifiedAt': freshRemoteStatus.modifiedAt
                    ?.toUtc()
                    .toIso8601String(),
              },
            );
            state = state.copyWith(
              stage: SyncTransferStage.error,
              message: 'sync.error.conflict_download_first_or_force_upload',
              remoteStatus: freshRemoteStatus,
            );
            await _recordSyncHistory(
              startedAt: historyStartedAt,
              operation: 'upload',
              success: false,
              message: state.message,
              queueBefore: queueBeforeUpload,
              remoteStatus: freshRemoteStatus,
              localBundle: bundle,
            );
            return;
          }
        }
      }
      if (expectedRemoteFileId == null) {
        final finalHistory = await _listReplayHistory(const SyncBundleState());
        final finalKnown =
            (await ref.read(syncBundleStateStoreProvider).read())
                .appliedRemoteFileIds ??
            const <String>{};
        if (finalHistory.any((item) => !finalKnown.contains(item.fileId))) {
          throw const SyncSafetyException(
            'sync.error.conflict_download_first_or_force_upload',
          );
        }
      }
      final replayBaseFileId = !uploadAdvertisesFullSnapshot
          ? null
          : recoveringFullHistory
          ? '__root__'
          : bundleStateBeforeUpload.lastAppliedRemoteFileId ?? '__root__';
      final remoteStatus = await runFirebaseTrace(
        'sync_upload_remote_bundle',
        () => _uploadRemoteBundle(
          encodedPayload: encodedPayload,
          deviceId: snapshot.deviceId,
          noteCount: bundle.noteCount,
          attachmentCount: bundle.attachmentCount,
          bundleKind: uploadAdvertisesFullSnapshot
              ? 'full-ids-v1'
              : uploadBundleKind,
          replayBaseFileId: replayBaseFileId,
        ),
      );
      _cacheRemoteStatus(provider, remoteStatus);
      _diagnostic(
        'remote bundle uploaded',
        data: {
          'fileId': remoteStatus.fileId,
          'modifiedAt': remoteStatus.modifiedAt?.toUtc().toIso8601String(),
          'deviceId': remoteStatus.deviceId,
          'notes': remoteStatus.noteCount,
          'attachments': remoteStatus.attachmentCount,
          'sizeBytes': remoteStatus.sizeBytes,
        },
      );
      _setProgress(SyncTransferProgress.finalizing);
      await _yieldToUi();
      await ref
          .read(notesControllerProvider.notifier)
          .markSnapshotChangesSynced(
            {
              ...publicPendingHashes,
              for (final entry in encryptedPrivateNotes)
                entry.note.id: entry.note.contentHash,
            },
            preparedNotes: [
              ...snapshot.notes,
              ...privateSyncPayload.preparedNotes,
            ],
          );
      if (encryptedPrivateNoteIds.isNotEmpty) {
        final encryptedDatabase = ref.read(encryptedNoteDatabaseProvider);
        final localSnapshots = {
          for (final local in await encryptedDatabase.loadAll())
            local.note.id: local,
        };
        for (final entry in encryptedPrivateNotes) {
          final local = localSnapshots[entry.note.id];
          // The export contains cloud references. Keep the original local
          // payload paths, including for profiles absent from the current
          // in-memory view, and never overwrite edits made during upload.
          if (local == null ||
              local.note.contentHash != entry.note.contentHash ||
              local.note.revision > entry.note.revision ||
              local.note.syncState == NoteSyncState.synced) {
            continue;
          }
          await encryptedDatabase.upsertOne(
            note: local.note.copyWith(
              syncState: NoteSyncState.synced,
              revision: entry.note.revision,
              deletedAt: entry.note.deletedAt,
              clearDeletedAt: entry.action == PendingNoteChangeAction.upsert,
            ),
            attachments: local.attachments,
          );
        }
      }
      ref.invalidate(syncQueueSummaryProvider);
      final queueAfterUpload = await _readLocalSyncQueueSummary();
      _diagnostic(
        'local queue after upload marked synced',
        data: {
          'changes': queueAfterUpload.totalChanges,
          'upserts': queueAfterUpload.upserts,
          'deletes': queueAfterUpload.deletes,
        },
      );
      state = SyncTransferState(
        stage: SyncTransferStage.success,
        message: 'sync.info.upload_success',
        remoteStatus: remoteStatus,
        localBundle: bundle,
      );
      await ref
          .read(syncBundleStateStoreProvider)
          .recordUpload(
            remoteStatus,
            fullSnapshot: uploadAdvertisesFullSnapshot,
            advanceAppliedAnchor: false,
          );
      ref.invalidate(syncBundleStateProvider);
      await _recordSyncHistory(
        startedAt: historyStartedAt,
        operation: 'upload',
        success: true,
        message: state.message,
        queueBefore: queueBeforeUpload,
        queueAfter: queueAfterUpload,
        remoteStatus: remoteStatus,
        localBundle: bundle,
      );
      if (_managedAttachmentTransport() != null) {
        try {
          await _finishAttachmentReservation(uploadId, remoteStatus.fileId);
        } catch (_) {
          _diagnostic('published attachment reservation release deferred');
        }
      }
      if (pruneAfterUpload && uploadAdvertisesFullSnapshot) {
        try {
          await _safePruneRemoteHistory(remoteStatus);
        } catch (_) {
          _diagnostic('remote history cleanup deferred');
        }
      }
    } on SyncAttachmentMissingException catch (error) {
      _diagnostic(
        'upload blocked by missing local attachment',
        data: {
          'noteId': error.noteId,
          'attachmentLabel': error.attachmentLabel,
          'attachmentType': error.attachmentType.name,
          'fileRef': path.basename(error.filePath),
          'index': error.index,
        },
      );
      if (await _restoreMissingAttachmentRemoteRefFromLatestBundle(error)) {
        _diagnostic(
          'missing local attachment restored from remote reference',
          data: {
            'noteId': error.noteId,
            'attachmentLabel': error.attachmentLabel,
            'index': error.index,
          },
        );
        await uploadCurrentBundle(
          force: force,
          fullSnapshot: fullSnapshot,
          deltaOnly: deltaOnly,
          expectedRemoteFileId: expectedRemoteFileId,
          onlyPendingNoteIds: onlyPendingNoteIds,
          allowLargeMobileTransfer: allowLargeMobileTransfer,
          silentLargeMobileSkip: silentLargeMobileSkip,
          pruneAfterUpload: pruneAfterUpload,
        );
        return;
      }
      state = _failureState(
        error,
        remoteStatus: state.remoteStatus,
        localBundle: state.localBundle,
      );
      await _recordSyncHistory(
        startedAt: historyStartedAt,
        operation: 'upload',
        success: false,
        message: state.message,
        queueBefore: queueBeforeUpload,
        remoteStatus: state.remoteStatus,
        localBundle: state.localBundle,
      );
    } catch (error) {
      _diagnostic('upload failed', data: {'error': error});
      state = _failureState(
        error,
        remoteStatus: state.remoteStatus,
        localBundle: state.localBundle,
      );
      await _recordSyncHistory(
        startedAt: historyStartedAt,
        operation: 'upload',
        success: false,
        message: state.message,
        queueBefore: queueBeforeUpload,
        remoteStatus: state.remoteStatus,
        localBundle: state.localBundle,
      );
    }
  }

  Future<_PreparedPrivateSyncPayload> _preparePrivateSyncNotes(
    List<PendingNoteChangeRecord> pendingChanges, {
    required bool includeAllPrivateSnapshots,
    Set<String>? remoteAttachmentContentHashes,
  }) async {
    final privateChanges = pendingChanges
        .where((change) => isPrivateVaultId(change.vaultId))
        .toList(growable: false);
    if (!includeAllPrivateSnapshots && privateChanges.isEmpty) {
      return const _PreparedPrivateSyncPayload(
        notes: <PreparedEncryptedPrivateSyncNote>[],
        attachments: <PreparedSyncAttachment>[],
        skippedLockedUpsertIds: <String>{},
      );
    }
    final privateChangesById = {
      for (final change in privateChanges) change.noteId: change,
    };
    final snapshots = await ref.read(encryptedNoteDatabaseProvider).loadAll();
    final encryptedNotes = <PreparedEncryptedPrivateSyncNote>[];
    final preparedNotes = <PreparedSyncNote>[];
    final attachmentObjects = <PreparedSyncAttachment>[];
    final preparedAttachmentHashes = <String>{};
    final skippedLockedUpsertIds = <String>{};
    final localAttachmentPathsByVault = <String, Map<String, String?>>{};
    final migratedAttachmentPaths = <String>{};

    Future<Map<String, String?>> localAttachmentPathsForVault(
      String vaultId,
    ) async {
      final cached = localAttachmentPathsByVault[vaultId];
      if (cached != null) {
        return cached;
      }
      final paths = await _localAttachmentPathsByContentHash(vaultId);
      localAttachmentPathsByVault[vaultId] = paths;
      return paths;
    }

    for (final snapshot in snapshots) {
      if (!isPrivateVaultId(snapshot.note.vaultId)) {
        continue;
      }
      final change = privateChangesById[snapshot.note.id];
      if (!includeAllPrivateSnapshots && change == null) {
        continue;
      }
      final action =
          change?.action ??
          (snapshot.note.deletedAt == null
              ? PendingNoteChangeAction.upsert
              : PendingNoteChangeAction.delete);
      var noteRecord = snapshot.note.copyWith(
        deletedAt: action == PendingNoteChangeAction.delete
            ? (change?.deletedAt ?? snapshot.note.deletedAt)
            : null,
        clearDeletedAt: action == PendingNoteChangeAction.upsert,
        revision: change == null
            ? snapshot.note.revision
            : math.max(snapshot.note.revision, change.revision),
        syncState: NoteSyncState.synced,
        contentHash: change?.contentHash ?? snapshot.note.contentHash,
      );
      var attachmentRecords = snapshot.attachments;
      final profileKey = await ref
          .read(profileDataKeyServiceProvider)
          .keyForVault(snapshot.note.vaultId);
      if (profileKey == null && action == PendingNoteChangeAction.upsert) {
        skippedLockedUpsertIds.add(snapshot.note.id);
        continue;
      }
      if (profileKey != null && action != PendingNoteChangeAction.delete) {
        final prepared = await _prepareUnlockedPrivateSyncNote(
          snapshot: snapshot,
          noteRecord: noteRecord,
          secretKey: profileKey,
          preparedAttachmentHashes: preparedAttachmentHashes,
          attachmentObjects: attachmentObjects,
          preparedNotes: preparedNotes,
          remoteAttachmentContentHashes: remoteAttachmentContentHashes,
          localAttachmentPathsBySyncHash: await localAttachmentPathsForVault(
            snapshot.note.vaultId,
          ),
          migratedAttachmentPaths: migratedAttachmentPaths,
        );
        noteRecord = prepared.note;
        attachmentRecords = prepared.attachments;
      }
      encryptedNotes.add(
        PreparedEncryptedPrivateSyncNote(
          action: action,
          note: noteRecord,
          attachments: attachmentRecords,
        ),
      );
    }
    return _PreparedPrivateSyncPayload(
      notes: encryptedNotes,
      preparedNotes: preparedNotes,
      attachments: attachmentObjects,
      skippedLockedUpsertIds: skippedLockedUpsertIds,
    );
  }

  Future<PreparedEncryptedPrivateSyncNote> _prepareUnlockedPrivateSyncNote({
    required EncryptedNoteSnapshot snapshot,
    required EncryptedNoteRecord noteRecord,
    required SecretKey secretKey,
    required Set<String> preparedAttachmentHashes,
    required List<PreparedSyncAttachment> attachmentObjects,
    required List<PreparedSyncNote> preparedNotes,
    Set<String>? remoteAttachmentContentHashes,
    required Map<String, String?> localAttachmentPathsBySyncHash,
    required Set<String> migratedAttachmentPaths,
  }) async {
    final encryptionService = ref.read(encryptionServiceProvider);
    final attachmentStore = ref.read(encryptedAttachmentStoreProvider);
    final payload = await encryptionService.decryptJson(
      encodedPayload: snapshot.note.encryptedPayload,
      secretKey: secretKey,
    );
    final decodedAttachments = <NoteAttachment>[];
    for (final attachmentRecord in snapshot.attachments) {
      final attachmentPayload = await encryptionService.decryptJson(
        encodedPayload: attachmentRecord.encryptedPayload,
        secretKey: secretKey,
      );
      decodedAttachments.add(NoteAttachment.fromJson(attachmentPayload));
    }
    final legacyAttachments =
        (payload['attachments'] as List<dynamic>? ?? const <dynamic>[])
            .map((entry) => Map<String, dynamic>.from(entry as Map))
            .map(NoteAttachment.fromJson)
            .toList(growable: false);
    final note =
        NoteEntry.fromJson({
          ...payload,
          'attachments':
              (decodedAttachments.isNotEmpty
                      ? decodedAttachments
                      : legacyAttachments)
                  .map((attachment) => attachment.toJson())
                  .toList(),
        }).copyWith(
          createdAt: noteRecord.createdAt,
          updatedAt: noteRecord.updatedAt,
          deletedAt: noteRecord.deletedAt,
          isPinned: noteRecord.isPinned,
          revision: noteRecord.revision,
          syncState: noteRecord.syncState,
          deviceId: noteRecord.deviceId,
          contentHash: noteRecord.contentHash,
        );
    final attachmentIdsByPath = <String, String>{};

    void addPreparedAttachmentObject(PreparedSyncAttachment attachment) {
      if (preparedAttachmentHashes.add(attachment.contentHash)) {
        attachmentObjects.add(attachment);
        return;
      }
      final existingIndex = attachmentObjects.indexWhere(
        (entry) => entry.contentHash == attachment.contentHash,
      );
      if (existingIndex == -1) {
        return;
      }
      final existing = attachmentObjects[existingIndex];
      if (!_preparedSyncAttachmentHasPayload(existing) &&
          _preparedSyncAttachmentHasPayload(attachment)) {
        attachmentObjects[existingIndex] = attachment;
      }
    }

    void addAttachmentReferenceMetadata(
      NoteAttachment attachment,
      String contentHash, {
      int? sizeBytes,
    }) {
      addPreparedAttachmentObject(
        PreparedSyncAttachment(
          id: contentHash,
          type: attachment.type,
          label: attachment.label,
          contentHash: contentHash,
          sizeBytes: sizeBytes ?? attachment.localPayloadSizeBytes ?? 0,
        ),
      );
    }

    Future<NoteAttachment> prepareAttachment(
      NoteAttachment attachment,
      int index,
    ) async {
      var filePath = attachment.filePath;
      if (filePath == null || filePath.isEmpty) {
        return attachment.copyWith(filePath: null, previewBytesBase64: null);
      }
      if (isSyncAttachmentObjectRef(filePath)) {
        final contentHash = syncAttachmentObjectContentHash(filePath);
        if (contentHash == null) {
          return attachment;
        }
        if (remoteAttachmentContentHashes != null &&
            !remoteAttachmentContentHashes.contains(contentHash)) {
          final localPath = localAttachmentPathsBySyncHash[contentHash];
          if (localPath == null || localPath.isEmpty) {
            // This reference has no local payload to re-materialize.  Keep it
            // out of the local-file repair path, which would otherwise
            // restore the same stale reference and retry forever.
            throw StateError(
              'sync.error.remote_attachment_unavailable '
              'noteId=${note.id} contentHash=$contentHash',
            );
          }
          filePath = localPath;
        } else {
          addAttachmentReferenceMetadata(attachment, contentHash);
          return attachment.copyWith(syncAttachmentContentHash: contentHash);
        }
      }
      if (attachmentIdsByPath[filePath] case final existingId?) {
        final metadata = await attachmentStore.storedPayloadMetadata(filePath);
        return attachment.copyWith(
          filePath: syncAttachmentObjectRef(
            existingId,
            managed: _managedAttachmentTransport() != null,
          ),
          localPayloadSizeBytes: metadata?.sizeBytes,
          localPayloadModifiedAtMillis: metadata?.modifiedAtMillis,
          syncAttachmentContentHash: existingId,
        );
      }
      if (await attachmentStore.migrateLegacyPrivateAttachment(
        filePath,
        type: attachment.type,
        vaultId: note.vaultId,
      )) {
        migratedAttachmentPaths.add(filePath);
      }
      final storedMetadata = await attachmentStore.storedPayloadMetadata(
        filePath,
      );
      final cachedContentHash = migratedAttachmentPaths.contains(filePath)
          ? null
          : attachment.syncAttachmentContentHash;
      if (cachedContentHash != null &&
          cachedContentHash.isNotEmpty &&
          storedMetadata != null &&
          attachment.localPayloadSizeBytes == storedMetadata.sizeBytes &&
          attachment.localPayloadModifiedAtMillis != null &&
          attachment.localPayloadModifiedAtMillis ==
              storedMetadata.modifiedAtMillis &&
          remoteAttachmentContentHashes != null &&
          remoteAttachmentContentHashes.contains(cachedContentHash)) {
        addAttachmentReferenceMetadata(
          attachment,
          cachedContentHash,
          sizeBytes: storedMetadata.sizeBytes,
        );
        return attachment.copyWith(
          filePath: syncAttachmentObjectRef(
            cachedContentHash,
            managed: _managedAttachmentTransport() != null,
          ),
          localPayloadSizeBytes: storedMetadata.sizeBytes,
          localPayloadModifiedAtMillis: storedMetadata.modifiedAtMillis,
        );
      }
      final encryptedPayload = await attachmentStore.readStoredPayload(
        filePath,
      );
      if (encryptedPayload == null || encryptedPayload.isEmpty) {
        throw SyncAttachmentMissingException(
          noteId: note.id,
          attachmentLabel: attachment.label,
          attachmentType: attachment.type,
          filePath: filePath,
          index: index,
        );
      }
      final contentHash = await _encryptedAttachmentPayloadContentHash(
        encryptedPayload,
      );
      attachmentIdsByPath[filePath] = contentHash;
      addPreparedAttachmentObject(
        PreparedSyncAttachment(
          id: contentHash,
          type: attachment.type,
          label: attachment.label,
          encryptedFilePath: filePath,
          contentHash: contentHash,
          sizeBytes: utf8.encode(encryptedPayload).length,
        ),
      );
      return attachment.copyWith(
        filePath: syncAttachmentObjectRef(
          contentHash,
          managed: _managedAttachmentTransport() != null,
        ),
        localPayloadSizeBytes: storedMetadata?.sizeBytes,
        localPayloadModifiedAtMillis: storedMetadata?.modifiedAtMillis,
        syncAttachmentContentHash: contentHash,
      );
    }

    final preparedAttachments = <NoteAttachment>[];
    for (var i = 0; i < note.attachments.length; i++) {
      preparedAttachments.add(await prepareAttachment(note.attachments[i], i));
    }
    final preparedBlocks = <NoteBlock>[];
    for (var i = 0; i < note.blocks.length; i++) {
      final block = note.blocks[i];
      final attachment = block.attachment;
      preparedBlocks.add(
        attachment == null
            ? block
            : block.copyWith(
                attachment: await prepareAttachment(
                  attachment,
                  note.attachments.length + i,
                ),
              ),
      );
    }
    final preparedNote = note.copyWith(
      attachments: preparedAttachments,
      blocks: preparedBlocks,
    );
    final notePayload = Map<String, dynamic>.from(preparedNote.toJson());
    notePayload['attachments'] = const <Map<String, dynamic>>[];
    final encryptedNotePayload = await encryptionService.encryptJson(
      payload: notePayload,
      secretKey: secretKey,
    );
    final encryptedAttachmentRecords = <EncryptedAttachmentRecord>[];
    for (var i = 0; i < preparedNote.attachments.length; i++) {
      encryptedAttachmentRecords.add(
        EncryptedAttachmentRecord(
          noteId: preparedNote.id,
          position: i,
          encryptedPayload: await encryptionService.encryptJson(
            payload: preparedNote.attachments[i].toJson(),
            secretKey: secretKey,
          ),
        ),
      );
    }
    preparedNotes.add(
      PreparedSyncNote(
        action: PendingNoteChangeAction.upsert,
        note: preparedNote,
      ),
    );
    return PreparedEncryptedPrivateSyncNote(
      action: PendingNoteChangeAction.upsert,
      note: EncryptedNoteRecord.fromNote(
        note: preparedNote,
        encryptedPayload: encryptedNotePayload,
      ),
      attachments: encryptedAttachmentRecords,
    );
  }

  Future<bool> _restoreMissingAttachmentRemoteRefFromLatestBundle(
    SyncAttachmentMissingException error,
  ) async {
    if (!_supportsRemoteTransport(ref.read(syncProviderControllerProvider))) {
      return false;
    }
    try {
      final remoteBundle = await _downloadLatestRemoteBundle();
      if (remoteBundle == null) {
        return false;
      }
      final localBundle = await ref
          .read(secureSyncBundleStoreProvider)
          .writeEncryptedBundlePayload(
            remoteBundle.encodedPayload,
            noteCount: remoteBundle.status.noteCount ?? 0,
            attachmentCount: remoteBundle.status.attachmentCount ?? 0,
            fileNameOverride: 'missing_attachment_repair_bundle.enc',
          );
      final decoded = await ref
          .read(secureSyncBundleStoreProvider)
          .readBundleJson(localBundle.reference);
      if (decoded == null) {
        return false;
      }
      final remoteAttachment = await _remoteAttachmentForMissingError(
        decodedBundle: decoded,
        error: error,
      );
      if (remoteAttachment == null ||
          !isSyncAttachmentObjectRef(remoteAttachment.filePath)) {
        return false;
      }
      return await ref
          .read(notesControllerProvider.notifier)
          .restoreMissingAttachmentRemoteReference(
            noteId: error.noteId,
            index: error.index,
            remoteAttachment: remoteAttachment,
          );
    } catch (repairError) {
      _diagnostic(
        'missing local attachment remote repair failed',
        data: {
          'noteId': error.noteId,
          'attachmentLabel': error.attachmentLabel,
          'error': repairError,
        },
      );
      return false;
    }
  }

  Future<NoteAttachment?> _remoteAttachmentForMissingError({
    required Map<String, dynamic> decodedBundle,
    required SyncAttachmentMissingException error,
  }) async {
    final rawNoteEntries =
        decodedBundle['notes'] as List<dynamic>? ?? const <dynamic>[];
    for (final rawEntry in rawNoteEntries) {
      if (rawEntry is! Map) {
        continue;
      }
      final rawNote = rawEntry['note'];
      if (rawNote is! Map) {
        continue;
      }
      final note = NoteEntry.fromJson(Map<String, dynamic>.from(rawNote));
      if (note.id != error.noteId) {
        continue;
      }
      final remoteAttachment = _attachmentAtSyncIndex(note, error.index);
      final remotePath = remoteAttachment?.filePath;
      if (remoteAttachment == null ||
          remoteAttachment.type != error.attachmentType ||
          !isSyncAttachmentObjectRef(remotePath)) {
        return null;
      }
      return remoteAttachment;
    }

    // Private notes are carried in encryptedPrivateNotes and therefore do
    // not expose their attachment metadata in the normal notes array.  When
    // the profile is unlocked, decrypt just the matching entry and recover
    // the same sync object reference used by the remote attachment bundle.
    final encryptedPrivateEntries =
        decodedBundle['encryptedPrivateNotes'] as List<dynamic>? ??
        const <dynamic>[];
    for (final rawEntry in encryptedPrivateEntries) {
      final entry = PreparedEncryptedPrivateSyncNote.fromJson(rawEntry);
      if (entry == null || entry.note.id != error.noteId) {
        continue;
      }
      final profileKey = await ref
          .read(profileDataKeyServiceProvider)
          .keyForVault(entry.note.vaultId);
      if (profileKey == null) {
        return null;
      }
      final encryptionService = ref.read(encryptionServiceProvider);
      final payload = await encryptionService.decryptJson(
        encodedPayload: entry.note.encryptedPayload,
        secretKey: profileKey,
      );
      final decodedAttachments = <NoteAttachment>[];
      for (final attachmentRecord in entry.attachments) {
        final attachmentPayload = await encryptionService.decryptJson(
          encodedPayload: attachmentRecord.encryptedPayload,
          secretKey: profileKey,
        );
        decodedAttachments.add(NoteAttachment.fromJson(attachmentPayload));
      }
      final legacyAttachments =
          (payload['attachments'] as List<dynamic>? ?? const <dynamic>[])
              .map((raw) => Map<String, dynamic>.from(raw as Map))
              .map(NoteAttachment.fromJson)
              .toList(growable: false);
      final note = NoteEntry.fromJson({
        ...payload,
        'attachments':
            (decodedAttachments.isNotEmpty
                    ? decodedAttachments
                    : legacyAttachments)
                .map((attachment) => attachment.toJson())
                .toList(),
      });
      final remoteAttachment = _attachmentAtSyncIndex(note, error.index);
      final remotePath = remoteAttachment?.filePath;
      if (remoteAttachment == null ||
          remoteAttachment.type != error.attachmentType ||
          !isSyncAttachmentObjectRef(remotePath)) {
        return null;
      }
      return remoteAttachment;
    }
    return null;
  }

  NoteAttachment? _attachmentAtSyncIndex(NoteEntry note, int index) {
    if (index < 0) {
      return null;
    }
    if (index < note.attachments.length) {
      return note.attachments[index];
    }
    final blockIndex = index - note.attachments.length;
    if (blockIndex < 0 || blockIndex >= note.blocks.length) {
      return null;
    }
    return note.blocks[blockIndex].attachment;
  }

  Future<void> reuploadAllCurrentNotes({
    bool allowLargeMobileTransfer = false,
    bool silentLargeMobileSkip = false,
  }) async {
    final provider = ref.read(syncProviderControllerProvider);
    if (!_supportsRemoteTransport(provider)) {
      state = const SyncTransferState(
        stage: SyncTransferStage.error,
        message: 'sync.error.select_target_for_reupload',
      );
      return;
    }
    if (state.isBusy) {
      return;
    }
    if (await _shouldBlockLargeMobileTransfer(
      allowLargeMobileTransfer: allowLargeMobileTransfer,
      silentLargeMobileSkip: silentLargeMobileSkip,
      includeDownload: false,
      estimateAllLocalNotes: true,
    )) {
      return;
    }
    _startBusy(SyncTransferProgress.preparingBundle);
    await _yieldToUi();
    await ref.read(notesControllerProvider.notifier).queueCurrentStateForSync();
    await uploadCurrentBundle(
      force: true,
      fullSnapshot: true,
      allowLargeMobileTransfer: allowLargeMobileTransfer,
      silentLargeMobileSkip: silentLargeMobileSkip,
    );
  }

  SyncBundleCoverage? _coverageFromBundle(Map<String, dynamic> decoded) {
    final raw = decoded['coverage'];
    if (raw == null) return null;
    final coverage = SyncBundleCoverage.tryParse(raw);
    if (coverage == null) throw const FormatException('Invalid sync coverage.');
    return coverage;
  }

  Future<List<RemoteSyncBundleStatus>> _selectReplayBundles(
    List<RemoteSyncBundleStatus> history,
    SyncBundleState applied,
  ) async {
    if (applied.appliedRemoteFileIds case final known?) {
      if (history.every((item) => known.contains(item.fileId))) return [];
    }
    SyncBundleCoverage? coverage;
    String? checkpointId;
    for (final item in history.where((item) => item.isFullBundle)) {
      final decoded = await _readRemoteBundleJsonById(item.fileId);
      coverage = _coverageFromBundle(decoded);
      if (coverage != null) {
        checkpointId = item.fileId;
        break;
      }
    }
    // An old chronological anchor cannot prove which older IDs were observed.
    final knownState = applied.appliedRemoteFileIds == null
        ? applied.copyWith(appliedRemoteFileIds: <String>{})
        : applied;
    return selectRemoteBundlesToApply(
      history: history,
      bundleState: knownState,
      coverage: coverage,
      coverageBundleId: checkpointId,
    );
  }

  SyncExclusionRetention? _exclusionRetentionFromBundle(
    Map<String, dynamic> decoded,
  ) {
    final raw = decoded['exclusionRetention'];
    if (raw == null) return null;
    final retention = SyncExclusionRetention.fromJson(raw);
    if (retention == null) {
      throw const FormatException('Invalid excluded-note retention manifest.');
    }
    return retention;
  }

  Future<Map<String, dynamic>> _readRemoteBundleJsonById(String fileId) async {
    final downloaded = await _downloadRemoteBundleById(fileId);
    if (downloaded == null) {
      throw const SyncSafetyException('sync.error.remote_bundle_missing');
    }
    return ref
        .read(secureSyncBundleStoreProvider)
        .readRemoteBundlePayloadJson(downloaded.encodedPayload);
  }

  Future<SyncExclusionRetention> _prepareExclusionRetention() async {
    final excludedTags = ref.read(syncExclusionTagsControllerProvider);
    final localExcludedIds = {
      for (final note in ref.read(notesControllerProvider))
        if (noteExcludedFromSync(note, excludedTags)) note.id,
    };
    final localIds = ref
        .read(notesControllerProvider)
        .map((note) => note.id)
        .toSet();
    final builder = SyncExclusionRetentionBuilder(
      localExcludedNoteIds: localExcludedIds,
      isExcluded: (note) =>
          noteExcludedFromSync(note, excludedTags) ||
          !localIds.contains(note.id),
    );
    final history = await _listReplayHistory(const SyncBundleState());
    for (final item in history) {
      final decoded = await _readRemoteBundleJsonById(item.fileId);
      // Source entries stay in their original encrypted bundles. Checkpoints
      // need only small ID manifests, not copies of every excluded payload.
      builder.addBundle(
        fileId: item.fileId,
        payload: decoded,
        modifiedAt: item.modifiedAt,
      );
      await _yieldToUi();
    }
    return builder.finish();
  }

  /// Resolve only the declared note versions. Importing an entire dependency
  /// could resurrect unrelated notes removed in the newer full snapshot.
  Future<void> _expandExcludedRemoteNotes(Map<String, dynamic> decoded) async {
    final retention = _exclusionRetentionFromBundle(decoded);
    if (retention == null || retention.noteBundleIds.isEmpty) return;
    final notes = <dynamic>[...?decoded['notes'] as List<dynamic>?];
    final presentIds = <String>{
      for (final raw in notes)
        if (raw is Map && raw['note'] is Map)
          (raw['note'] as Map)['id'] as String,
    };
    final attachments = <String, dynamic>{
      for (final raw in decoded['attachments'] as List<dynamic>? ?? const [])
        if (raw is Map && raw['id'] is String) raw['id'] as String: raw,
    };
    final grouped = <String, Set<String>>{};
    for (final entry in retention.noteBundleIds.entries) {
      if (!presentIds.contains(entry.key)) {
        grouped.putIfAbsent(entry.value, () => {}).add(entry.key);
      }
    }
    for (final entry in grouped.entries) {
      final source = await _readRemoteBundleJsonById(entry.key);
      final missingIds = {...entry.value};
      final neededAttachmentIds = <String>{};
      void addAttachmentId(Object? value) {
        if (value is! Map) return;
        final filePath = value['filePath'];
        if (filePath is! String) return;
        final hash = syncAttachmentObjectContentHash(filePath);
        if (hash != null) neededAttachmentIds.add(hash);
        if (filePath.startsWith('sync-attachment://')) {
          neededAttachmentIds.add(
            filePath.substring('sync-attachment://'.length),
          );
        }
      }

      for (final raw in source['notes'] as List<dynamic>? ?? const []) {
        if (raw is! Map || raw['note'] is! Map) continue;
        final id = (raw['note'] as Map)['id'];
        if (!missingIds.remove(id)) continue;
        final rawNote = raw['note'] as Map;
        for (final attachment
            in rawNote['attachments'] as List<dynamic>? ?? const []) {
          addAttachmentId(attachment);
        }
        for (final block in rawNote['blocks'] as List<dynamic>? ?? const []) {
          if (block is Map) addAttachmentId(block['attachment']);
        }
        notes.add(raw);
      }
      if (missingIds.isNotEmpty) {
        throw const SyncSafetyException('sync.error.remote_history_incomplete');
      }
      for (final raw in source['attachments'] as List<dynamic>? ?? const []) {
        if (raw is Map && raw['id'] is String) {
          final id = raw['id'] as String;
          if (!neededAttachmentIds.contains(id)) continue;
          final existing = attachments[id];
          if (existing is Map &&
              (existing['contentHash'] != raw['contentHash'] ||
                  (existing['bytesBase64'] != null &&
                      raw['bytesBase64'] != null &&
                      existing['bytesBase64'] != raw['bytesBase64']) ||
                  (existing['encryptedPayload'] != null &&
                      raw['encryptedPayload'] != null &&
                      existing['encryptedPayload'] !=
                          raw['encryptedPayload']))) {
            throw const FormatException(
              'Conflicting retained attachment identifiers.',
            );
          }
          attachments[id] = existing ?? raw;
        }
      }
    }
    decoded['notes'] = notes;
    decoded['attachments'] = attachments.values.toList();
  }

  /// Delete only an enumerated prefix represented by this full snapshot.
  /// Attachment objects are intentionally retained: an unreferenced object can
  /// belong to another device's upload which has not published its bundle yet.
  Future<ICloudMaintenanceResult> _safePruneRemoteHistory(
    RemoteSyncBundleStatus published, {
    int keepLatest = 3,
  }) async {
    final bundles = await _pruneCoveredRemoteBundles(
      published,
      keepLatest: keepLatest,
    );
    final objects = await _collectUnreferencedAttachments();
    final live = await _listReplayHistory(const SyncBundleState());
    await ref
        .read(syncBundleStateStoreProvider)
        .retainAppliedIds(live.map((item) => item.fileId).toSet());
    return ICloudMaintenanceResult(
      deletedBundleCount: bundles.deletedBundleCount,
      deletedBundleBytes: bundles.deletedBundleBytes,
      deletedAttachmentCount: objects.$1,
      deletedAttachmentBytes: objects.$2,
    );
  }

  Future<(int, int)> _collectUnreferencedAttachments() async {
    final transport = _managedAttachmentTransport();
    if (transport == null) return (0, 0);
    // Snapshot object revisions BEFORE enumerating bundle references. A writer
    // pin or publication/release after this point invalidates the CAS token.
    final candidates = await transport.listManagedAttachmentObjects();
    final history = await _listReplayHistory(const SyncBundleState());
    final referenced = <String>{};
    final liveIds = history.map((item) => item.fileId).toSet();
    for (final status in history) {
      final decoded = await _readRemoteBundleJsonById(status.fileId);
      for (final raw in decoded['attachments'] as List<dynamic>? ?? const []) {
        if (raw is Map && raw['contentHash'] is String) {
          referenced.add(raw['contentHash'] as String);
        }
      }
      for (final raw in decoded['notes'] as List<dynamic>? ?? const []) {
        if (raw is Map && raw['note'] is Map) {
          referenced.addAll(
            syncAttachmentObjectHashesInNoteJson(raw['note'] as Map),
          );
        }
      }
    }
    var count = 0;
    var bytes = 0;
    final before = DateTime.now().toUtc().subtract(const Duration(days: 7));
    for (final item in candidates) {
      if (item.uploadIds.isNotEmpty ||
          item.modifiedAt == null ||
          item.modifiedAt!.isAfter(before) ||
          referenced.contains(item.contentHash)) {
        continue;
      }
      final lastPublication = item.lastPublishedBundleId;
      if (lastPublication != null) {
        if (liveIds.contains(lastPublication)) continue;
        try {
          if (await _downloadRemoteBundleById(lastPublication) != null) {
            continue;
          }
        } on GoogleDriveSyncException catch (error) {
          if (error.statusCode != 404) continue;
        } catch (_) {
          // Failure is not proof that a hinted publication no longer exists.
          continue;
        }
      }
      if (await transport.claimAndDeleteAttachmentObject(item)) {
        count++;
        bytes += item.sizeBytes;
      }
    }
    return (count, bytes);
  }

  Future<ICloudMaintenanceResult> _pruneCoveredRemoteBundles(
    RemoteSyncBundleStatus published, {
    int keepLatest = 3,
  }) async {
    const empty = ICloudMaintenanceResult(
      deletedBundleCount: 0,
      deletedBundleBytes: 0,
      deletedAttachmentCount: 0,
      deletedAttachmentBytes: 0,
    );
    if (!published.isFullBundle || published.replayBaseFileId == null) {
      return empty;
    }
    final history = await _listReplayHistory(const SyncBundleState());
    if (history.isEmpty || history.first.fileId != published.fileId) {
      return empty;
    }
    final publishedPayload = await _readRemoteBundleJsonById(published.fileId);
    final coverage = _coverageFromBundle(publishedPayload);
    if (coverage == null) return empty;
    final preserve = keepLatest < 1 ? 1 : keepLatest;
    final retained =
        history
            .where((item) => !coverage.coveredBundleIds.contains(item.fileId))
            .map((item) => item.fileId)
            .toSet()
          ..addAll(history.take(preserve).map((item) => item.fileId))
          ..add(published.fileId);
    final protectedIds = <String>{};
    for (final retained in history.where(
      (item) => retained.contains(item.fileId) && item.isFullBundle,
    )) {
      final decoded = await _readRemoteBundleJsonById(retained.fileId);
      protectedIds.addAll(
        _exclusionRetentionFromBundle(decoded)?.retainedBundleIds ??
            const <String>{},
      );
    }
    final candidates = history
        .where(
          (item) =>
              coverage.coveredBundleIds.contains(item.fileId) &&
              !retained.contains(item.fileId) &&
              !protectedIds.contains(item.fileId),
        )
        .toList();
    if (candidates.isEmpty) return empty;
    // This check helps avoid unnecessary cleanup during active writes. Safety
    // also comes from exact IDs: a subsequent publication is never selected.
    if ((await _fetchLatestRemoteStatus())?.fileId != published.fileId) {
      return empty;
    }
    final ids = candidates.map((item) => item.fileId).toSet();
    final provider = ref.read(syncProviderControllerProvider);
    if (provider == SyncProvider.iCloud) {
      return ref
          .read(iCloudSyncTransportProvider)
          .pruneObsoleteData(
            keepLatest: preserve,
            referencedAttachmentHashes: const {},
            bundleFileIdsToDelete: ids,
            expectedLatestFileId: published.fileId,
          );
    }
    final transport = ref.read(googleDriveSyncTransportProvider);
    if (transport is! RemoteBundleMaintenanceTransport) return empty;
    await (transport as RemoteBundleMaintenanceTransport)
        .deleteBundleFilesByIds(ids);
    return ICloudMaintenanceResult(
      deletedBundleCount: ids.length,
      deletedBundleBytes: candidates.fold<int>(
        0,
        (sum, item) => sum + (item.sizeBytes ?? 0),
      ),
      deletedAttachmentCount: 0,
      deletedAttachmentBytes: 0,
    );
  }

  Future<List<RemoteSyncBundleStatus>> _listReplayHistory(
    SyncBundleState applied,
  ) async {
    try {
      return await readSyncReplayHistory(
        fetch: (limit) => _listRemoteHistory(limit: limit),
        applied: applied,
        requireComplete: true,
        initialLimit: _remoteBundleWalkHistoryLimit,
      );
    } catch (error) {
      _diagnostic(
        'complete remote history unavailable',
        data: {'error': error},
      );
      throw const SyncSafetyException('sync.error.remote_history_incomplete');
    }
  }

  Future<({bool ready, bool recoveringFullHistory})> _applyRemoteBeforeUpload({
    bool allowIncompleteHistory = false,
    bool allowLargeMobileTransfer = false,
    bool silentLargeMobileSkip = false,
  }) async {
    var recoveringFullHistory = false;
    final latest = await _fetchLatestRemoteStatus();
    final applied = await ref.read(syncBundleStateStoreProvider).read();
    final history = await _listReplayHistory(applied);
    if (history.isEmpty) {
      if (latest != null) {
        throw const SyncSafetyException('sync.error.remote_history_incomplete');
      }
      return (ready: true, recoveringFullHistory: recoveringFullHistory);
    }
    final pendingBytes = history
        .where(
          (item) =>
              !(applied.appliedRemoteFileIds?.contains(item.fileId) ?? false),
        )
        .fold<int>(0, (total, item) => total + (item.sizeBytes ?? 0));
    if (await _shouldBlockLargeMobileTransfer(
      allowLargeMobileTransfer: allowLargeMobileTransfer,
      silentLargeMobileSkip: silentLargeMobileSkip,
      includeUpload: false,
      downloadBytesOverride: pendingBytes,
    )) {
      return (ready: false, recoveringFullHistory: recoveringFullHistory);
    }
    if (!remoteHistoryHasSafeReplayBase(
      history: history,
      bundleState: applied,
    )) {
      if (!allowIncompleteHistory) {
        throw const SyncSafetyException('sync.error.remote_history_incomplete');
      }
      recoveringFullHistory = true;
    }
    for (final item in await _selectReplayBundles(history, applied)) {
      if (item.fileId == applied.lastUploadedRemoteFileId) {
        final decoded = await _readRemoteBundleJsonById(item.fileId);
        await ref
            .read(syncBundleStateStoreProvider)
            .recordApply(
              item,
              coveredRemoteFileIds:
                  _coverageFromBundle(decoded)?.coveredBundleIds ?? const {},
            );
        continue;
      }
      final remote = await _downloadRemoteBundleById(item.fileId);
      if (remote == null) {
        throw const SyncSafetyException('sync.error.remote_bundle_missing');
      }
      await _storeDownloadedBundle(
        remote,
        emptyMessage: 'sync.info.no_bundle_to_sync',
      );
      await applyDownloadedBundle(historyValidated: true);
      if (state.stage == SyncTransferStage.error) {
        return (ready: false, recoveringFullHistory: recoveringFullHistory);
      }
      final after = await ref.read(syncBundleStateStoreProvider).read();
      if (after.lastAppliedRemoteFileId != item.fileId) {
        return (ready: false, recoveringFullHistory: recoveringFullHistory);
      }
      if (ref
          .read(notesControllerProvider)
          .any((note) => note.syncState == NoteSyncState.conflict)) {
        state = state.copyWith(
          stage: SyncTransferStage.error,
          message: 'sync.error.conflict_review_remote',
        );
        return (ready: false, recoveringFullHistory: recoveringFullHistory);
      }
    }
    return (ready: true, recoveringFullHistory: recoveringFullHistory);
  }

  Future<void> syncNow({
    bool forceUpload = false,
    bool allowLargeMobileTransfer = false,
    bool silentLargeMobileSkip = false,
    bool allowCachedRemoteStatus = true,
  }) async {
    final provider = ref.read(syncProviderControllerProvider);
    _diagnostic(
      'sync now requested',
      data: {
        'provider': provider.name,
        'forceUpload': forceUpload,
        'busy': state.isBusy,
        'allowCachedRemoteStatus': allowCachedRemoteStatus,
      },
    );
    if (!_supportsRemoteTransport(provider)) {
      _diagnostic(
        'sync now skipped unsupported provider',
        data: {'provider': provider.name},
      );
      return;
    }
    if (state.isBusy) {
      _diagnostic('sync now skipped busy');
      return;
    }
    _startBusy(SyncTransferProgress.checkingRemote);
    await _yieldToUi();
    try {
      await logFirebaseBreadcrumb('sync now requested');
      const checkingStepCount = 4;
      _setProgressDetail(
        progress: SyncTransferProgress.checkingRemote,
        detail: 'Checking cloud status',
        completedItems: 0,
        totalItems: checkingStepCount,
      );
      await _yieldToUi();
      var remoteStatus = await _measureSyncStep(
        'remote status check completed',
        () => _fetchLatestRemoteStatusWithCache(
          traceName: 'sync_refresh_remote_status',
          allowCached: allowCachedRemoteStatus,
          totalItems: checkingStepCount,
        ),
        data: {'cachedAllowed': allowCachedRemoteStatus},
      );
      _setProgressDetail(
        progress: SyncTransferProgress.checkingRemote,
        detail: 'Reading sync history',
        completedItems: 1,
        totalItems: checkingStepCount,
      );
      await _yieldToUi();
      final bundleState = await _measureSyncStep(
        'sync state check completed',
        () => ref.read(syncBundleStateProvider.future),
      );
      final completeHistory = await _listReplayHistory(bundleState);
      if (completeHistory.isNotEmpty) remoteStatus = completeHistory.first;
      final pendingDownloadBytes = completeHistory
          .where(
            (item) =>
                !(bundleState.appliedRemoteFileIds?.contains(item.fileId) ??
                    false),
          )
          .fold<int>(0, (total, item) => total + (item.sizeBytes ?? 0));
      _diagnostic(
        'remote status refreshed',
        data: {
          'hasRemote': remoteStatus != null,
          'fileId': remoteStatus?.fileId,
          'modifiedAt': remoteStatus?.modifiedAt?.toUtc().toIso8601String(),
          'deviceId': remoteStatus?.deviceId,
          'notes': remoteStatus?.noteCount,
          'attachments': remoteStatus?.attachmentCount,
          'sizeBytes': remoteStatus?.sizeBytes,
          'lastRemoteFileId': bundleState.lastRemoteFileId,
          'lastAppliedAt': bundleState.lastAppliedAt?.toUtc().toIso8601String(),
          'lastUploadedAt': bundleState.lastUploadedAt
              ?.toUtc()
              .toIso8601String(),
        },
      );
      if (remoteStatus != null) {
        await ref
            .read(syncBundleStateStoreProvider)
            .recordRemoteStatus(remoteStatus);
      }
      state = state.copyWith(remoteStatus: remoteStatus);

      _setProgressDetail(
        progress: SyncTransferProgress.checkingRemote,
        detail: 'Checking transfer size',
        completedItems: 2,
        totalItems: checkingStepCount,
      );
      await _yieldToUi();
      if (await _measureSyncStep(
        'transfer size check completed',
        () => _shouldBlockLargeMobileTransfer(
          allowLargeMobileTransfer: allowLargeMobileTransfer,
          silentLargeMobileSkip: silentLargeMobileSkip,
          includeUpload: false,
          includeDownload: pendingDownloadBytes > 0,
          downloadBytesOverride: pendingDownloadBytes,
        ),
      )) {
        return;
      }

      _setProgressDetail(
        progress: SyncTransferProgress.checkingRemote,
        detail: 'Checking local changes',
        completedItems: 3,
        totalItems: checkingStepCount,
      );
      await _yieldToUi();
      final queue = await _measureSyncStep(
        'local queue check completed',
        _readLocalSyncQueueSummary,
      );
      final hadPendingChangesBeforeRemoteApply = queue.hasPendingChanges;
      var appliedRemoteDuringSync = false;
      var privateProfilesPendingUnlock = false;
      _diagnostic(
        'local queue inspected',
        data: {
          'changes': queue.totalChanges,
          'upserts': queue.upserts,
          'deletes': queue.deletes,
          'lastQueuedAt': queue.lastQueuedAt?.toUtc().toIso8601String(),
        },
      );
      final idReplay = await _selectReplayBundles(completeHistory, bundleState);
      if (idReplay.isNotEmpty) {
        _diagnostic(
          'remote bundle needs apply',
          data: {'fileId': completeHistory.first.fileId},
        );
        final assessment = assessSyncConflict(
          cloudSyncSelected: true,
          queue: queue,
          remoteStatus: remoteStatus,
          bundleState: bundleState,
        );
        if (assessment.hasConflict && !forceUpload) {
          _diagnostic(
            'sync conflict candidate detected',
            data: {'message': assessment.message},
          );
        }
        _setProgress(SyncTransferProgress.downloadingBundle);
        await _yieldToUi();
        // Delta sync: bundles may carry only a slice of the changes, so every
        // unapplied bundle since this device's apply anchor has to be walked
        // in order — applying just the newest one would drop the notes that
        // only exist in skipped intermediate bundles.
        final history = completeHistory;
        if (!remoteHistoryHasSafeReplayBase(
          history: history,
          bundleState: bundleState,
        )) {
          throw const SyncSafetyException(
            'sync.error.remote_history_incomplete',
          );
        }
        final bundlesToApply = idReplay;
        _diagnostic(
          'remote bundles selected for apply',
          data: {
            'historyCount': history.length,
            'applyCount': bundlesToApply.length,
            'fileIds': [for (final status in bundlesToApply) status.fileId]
                .join(','),
          },
        );
        for (final bundleStatus in bundlesToApply) {
          if (bundleStatus.fileId == bundleState.lastUploadedRemoteFileId) {
            final decoded = await _readRemoteBundleJsonById(
              bundleStatus.fileId,
            );
            await ref
                .read(syncBundleStateStoreProvider)
                .recordApply(
                  bundleStatus,
                  coveredRemoteFileIds:
                      _coverageFromBundle(decoded)?.coveredBundleIds ??
                      const {},
                );
            continue;
          }
          _setProgress(SyncTransferProgress.downloadingBundle);
          await _yieldToUi();
          final remoteBundle = await runFirebaseTrace(
            'sync_download_remote_bundle_for_apply',
            () => _downloadRemoteBundleById(bundleStatus.fileId),
          );
          if (remoteBundle == null) {
            _diagnostic(
              'remote bundle disappeared during walk',
              data: {'fileId': bundleStatus.fileId},
            );
            throw const SyncSafetyException('sync.error.remote_bundle_missing');
          }
          _diagnostic(
            'remote bundle downloaded for apply',
            data: {
              'fileId': remoteBundle.status.fileId,
              'bundleKind': remoteBundle.status.bundleKind,
              'payloadLength': remoteBundle.encodedPayload.length,
            },
          );
          await _storeDownloadedBundle(
            remoteBundle,
            emptyMessage: 'sync.info.no_bundle_to_sync',
          );
          _setProgress(SyncTransferProgress.applyingBundle);
          await _yieldToUi();
          // applyDownloadedBundle records the apply anchor per bundle, so an
          // interrupted walk resumes from the first bundle that was not yet
          // applied instead of starting over or skipping ahead.
          await applyDownloadedBundle(historyValidated: true);
          if (state.stage == SyncTransferStage.error) {
            return;
          }
          if (state.message == _privateProfileNotesPendingUnlockMessage) {
            final appliedState = await ref
                .read(syncBundleStateStoreProvider)
                .read();
            if (appliedState.lastAppliedRemoteFileId != bundleStatus.fileId) {
              // A legacy private entry was skipped, so replaying subsequent
              // deltas would move past data that has not been stored locally.
              return;
            }
            privateProfilesPendingUnlock = true;
          }
          appliedRemoteDuringSync = true;
          final hasNoteConflicts = ref
              .read(notesControllerProvider)
              .any((note) => note.syncState == NoteSyncState.conflict);
          if (hasNoteConflicts && !forceUpload) {
            _diagnostic('sync note conflict requires review');
            state = state.copyWith(
              stage: SyncTransferStage.error,
              message: 'sync.error.conflict_review_remote',
            );
            return;
          }
        }
      }

      ref.invalidate(syncQueueSummaryProvider);
      final refreshedQueue = await _readLocalSyncQueueSummary();
      _diagnostic(
        'local queue refreshed',
        data: {
          'changes': refreshedQueue.totalChanges,
          'upserts': refreshedQueue.upserts,
          'deletes': refreshedQueue.deletes,
        },
      );
      if (refreshedQueue.hasPendingChanges) {
        _setProgress(SyncTransferProgress.preparingBundle);
        await _yieldToUi();
        final forceConvergenceUpload =
            appliedRemoteDuringSync && !hadPendingChangesBeforeRemoteApply;
        await uploadCurrentBundle(
          force: forceUpload || forceConvergenceUpload,
          allowLargeMobileTransfer: allowLargeMobileTransfer,
          silentLargeMobileSkip: silentLargeMobileSkip,
        );
        return;
      }
      _setProgress(SyncTransferProgress.finalizing);
      await _yieldToUi();
      state = SyncTransferState(
        stage: SyncTransferStage.success,
        message: privateProfilesPendingUnlock
            ? _privateProfileNotesPendingUnlockMessage
            : 'sync.info.sync_success',
        remoteStatus: state.remoteStatus,
        localBundle: state.localBundle,
      );
      _diagnostic('sync now completed');
    } catch (error) {
      _diagnostic('sync now failed', data: {'error': error});
      state = _failureState(
        error,
        remoteStatus: state.remoteStatus,
        localBundle: state.localBundle,
      );
    }
  }

  Future<LocalNoteArchive> exportLocalArchive({
    String? password,
    Set<String>? vaultIds,
    bool includeSampleNotes = false,
  }) async {
    _startBusy(SyncTransferProgress.preparingBundle);
    try {
      await logFirebaseBreadcrumb('local zip archive export requested');
      final archive = await runFirebaseTrace(
        'notes_prepare_local_zip_archive',
        () => _buildLocalZipArchive(
          password: password,
          vaultIds: vaultIds,
          includeSampleNotes: includeSampleNotes,
        ),
      );
      if (archive.bytes.isEmpty) {
        throw StateError('ローカルアーカイブを準備できませんでした。');
      }
      state = SyncTransferState(
        stage: SyncTransferStage.success,
        message:
            'ZIP アーカイブを作成しました（ノート ${archive.noteCount} 件、添付 ${archive.attachmentCount} 件）。',
        remoteStatus: state.remoteStatus,
        localBundle: state.localBundle,
      );
      return archive;
    } catch (error) {
      state = _failureState(
        error,
        remoteStatus: state.remoteStatus,
        localBundle: state.localBundle,
      );
      rethrow;
    }
  }

  Future<SyncBundlePreview> importLocalArchiveBytes(
    List<int> bytes, {
    String? password,
  }) async {
    if (bytes.isEmpty) {
      throw StateError('選択したアーカイブは空です。');
    }
    _startBusy(SyncTransferProgress.preparingBundle);
    try {
      await logFirebaseBreadcrumb('local zip archive import selected');
      final decoded = await _decodeLocalZipArchive(bytes, password: password);
      final preview = buildSyncBundlePreview(
        decodedBundle: _zipArchiveAsSyncBundle(decoded),
        currentNotes: ref.read(notesControllerProvider),
      );
      state = SyncTransferState(
        stage: SyncTransferStage.success,
        message: '確認用の ZIP アーカイブを読み込みました。',
        remoteStatus: state.remoteStatus,
        localBundle: state.localBundle,
      );
      return preview;
    } catch (error) {
      state = _failureState(
        error,
        remoteStatus: state.remoteStatus,
        localBundle: state.localBundle,
      );
      rethrow;
    }
  }

  Future<void> applyLocalArchiveBytes(
    List<int> bytes, {
    String? password,
  }) async {
    _startBusy(SyncTransferProgress.applyingBundle);
    try {
      await logFirebaseBreadcrumb('local zip archive apply selected');
      final decoded = await _decodeLocalZipArchive(bytes, password: password);
      final attachmentFiles = decoded.attachmentFiles;
      final importedChanges = <PreparedSyncNote>[];
      for (final rawNote in decoded.notes) {
        final note = NoteEntry.fromJson(rawNote);
        final storedByArchivePath = <String, String?>{};

        Future<NoteAttachment> importAttachment(
          NoteAttachment attachment,
        ) async {
          final filePath = attachment.filePath;
          if (filePath == null || filePath.isEmpty) {
            return attachment.copyWith(
              filePath: null,
              previewBytesBase64: null,
            );
          }
          final bytes = attachmentFiles[filePath];
          if (bytes == null || bytes.isEmpty) {
            return attachment.copyWith(
              filePath: null,
              previewBytesBase64: null,
            );
          }
          if (!storedByArchivePath.containsKey(filePath)) {
            final encryptedPayload = await ref
                .read(encryptedAttachmentStoreProvider)
                .encryptAttachmentBytes(
                  bytes: bytes,
                  type: attachment.type,
                  vaultId: note.vaultId,
                );
            storedByArchivePath[filePath] = await ref
                .read(encryptedAttachmentStoreProvider)
                .storeEncryptedPayload(
                  encodedPayload: encryptedPayload,
                  type: attachment.type,
                  fileNameHint: attachment.label,
                  vaultId: note.vaultId,
                );
          }
          return attachment.copyWith(
            filePath: storedByArchivePath[filePath],
            previewBytesBase64: null,
          );
        }

        final importedAttachments = <NoteAttachment>[];
        for (final attachment in note.attachments) {
          importedAttachments.add(await importAttachment(attachment));
        }
        final importedBlocks = <NoteBlock>[];
        for (final block in note.blocks) {
          final attachment = block.attachment;
          importedBlocks.add(
            attachment == null
                ? block
                : block.copyWith(
                    attachment: await importAttachment(attachment),
                  ),
          );
        }

        importedChanges.add(
          PreparedSyncNote(
            action: PendingNoteChangeAction.upsert,
            note: note.copyWith(
              attachments: importedAttachments,
              blocks: importedBlocks,
              syncState: NoteSyncState.pendingUpload,
            ),
          ),
        );
      }
      await ref
          .read(notesControllerProvider.notifier)
          .mergeFromSync(importedChanges);
      state = state.copyWith(
        stage: SyncTransferStage.success,
        message: 'ZIP アーカイブをローカルのノートに反映しました。',
      );
    } catch (error) {
      state = state.copyWith(stage: SyncTransferStage.error, message: '$error');
      rethrow;
    }
  }

  Future<void> downloadLatestBundle() async {
    final historyStartedAt = DateTime.now();
    final remoteStatus = state.remoteStatus;
    if (remoteStatus != null && remoteStatus.fileId.isNotEmpty) {
      await downloadBundle(remoteStatus);
      return;
    }
    final provider = ref.read(syncProviderControllerProvider);
    if (!_supportsRemoteTransport(provider)) {
      state = const SyncTransferState(
        stage: SyncTransferStage.error,
        message: 'sync.error.select_target_for_download',
      );
      await _recordSyncHistory(
        startedAt: historyStartedAt,
        operation: 'download',
        success: false,
        message: state.message,
      );
      return;
    }
    _startBusy(SyncTransferProgress.downloadingBundle);
    try {
      await logFirebaseBreadcrumb('sync download latest requested');
      final remoteBundle = await runFirebaseTrace(
        'sync_download_latest_bundle',
        _downloadLatestRemoteBundle,
      );
      await _storeDownloadedBundle(
        remoteBundle,
        emptyMessage: 'sync.info.no_usable_remote_bundle',
      );
      await _recordSyncHistory(
        startedAt: historyStartedAt,
        operation: 'download',
        success: state.stage == SyncTransferStage.success,
        message: state.message,
        remoteStatus: state.remoteStatus,
        localBundle: state.localBundle,
      );
    } catch (error) {
      state = _failureState(
        error,
        remoteStatus: state.remoteStatus,
        localBundle: state.localBundle,
      );
      await _recordSyncHistory(
        startedAt: historyStartedAt,
        operation: 'download',
        success: false,
        message: state.message,
        remoteStatus: state.remoteStatus,
        localBundle: state.localBundle,
      );
    }
  }

  Future<List<RemoteSyncBundleStatus>> listRemoteBundleHistory() async {
    return _listRemoteHistory();
  }

  Future<void> downloadBundle(RemoteSyncBundleStatus remoteStatus) async {
    final historyStartedAt = DateTime.now();
    final provider = ref.read(syncProviderControllerProvider);
    if (!_supportsRemoteTransport(provider)) {
      state = const SyncTransferState(
        stage: SyncTransferStage.error,
        message: 'sync.error.select_target_for_download',
      );
      await _recordSyncHistory(
        startedAt: historyStartedAt,
        operation: 'download',
        success: false,
        message: state.message,
        remoteStatus: remoteStatus,
      );
      return;
    }
    _startBusy(SyncTransferProgress.downloadingBundle);
    try {
      await logFirebaseBreadcrumb(
        'sync download bundle ${remoteStatus.fileId}',
      );
      final remoteBundle = await runFirebaseTrace(
        'sync_download_selected_bundle',
        () => _downloadRemoteBundleById(remoteStatus.fileId),
      );
      await _storeDownloadedBundle(
        remoteBundle,
        emptyMessage: 'sync.error.selected_bundle_download_failed',
      );
      await _recordSyncHistory(
        startedAt: historyStartedAt,
        operation: 'download',
        success: state.stage == SyncTransferStage.success,
        message: state.message,
        remoteStatus: state.remoteStatus ?? remoteStatus,
        localBundle: state.localBundle,
      );
    } catch (error) {
      state = _failureState(
        error,
        remoteStatus: state.remoteStatus,
        localBundle: state.localBundle,
      );
      await _recordSyncHistory(
        startedAt: historyStartedAt,
        operation: 'download',
        success: false,
        message: state.message,
        remoteStatus: state.remoteStatus ?? remoteStatus,
        localBundle: state.localBundle,
      );
    }
  }

  Future<SyncBundlePreview> downloadBundlePreview(
    RemoteSyncBundleStatus remoteStatus,
  ) async {
    await downloadBundle(remoteStatus);
    if (state.stage == SyncTransferStage.error) {
      throw StateError(
        state.message ?? 'sync.error.remote_bundle_download_failed',
      );
    }
    return previewDownloadedBundle();
  }

  Future<void> applyDownloadedBundle({bool historyValidated = false}) async {
    final historyStartedAt = DateTime.now();
    final localBundle = state.localBundle;
    if (localBundle == null) {
      state = state.copyWith(
        stage: SyncTransferStage.error,
        message: 'sync.error.download_before_apply',
      );
      await _recordSyncHistory(
        startedAt: historyStartedAt,
        operation: 'apply',
        success: false,
        message: state.message,
      );
      return;
    }
    final queueBeforeApply = await _readLocalSyncQueueSummary();
    _startBusy(SyncTransferProgress.applyingBundle);
    try {
      await logFirebaseBreadcrumb('sync apply downloaded bundle');
      final decoded = await runFirebaseTrace(
        'sync_read_downloaded_bundle',
        () => ref
            .read(secureSyncBundleStoreProvider)
            .readBundleJson(localBundle.reference),
      );
      if (decoded == null) {
        throw StateError('sync.error.downloaded_bundle_decryption_failed');
      }
      await _expandExcludedRemoteNotes(decoded);
      final encryptedDatabase = ref.read(encryptedNoteDatabaseProvider);
      final localPrivatePendingById = {
        for (final change in await encryptedDatabase.loadPendingChanges())
          if (isPrivateVaultId(change.vaultId)) change.noteId: change,
      };
      final existingPrivateSnapshotsById = {
        for (final snapshot in await encryptedDatabase.loadAll())
          if (isPrivateVaultId(snapshot.note.vaultId))
            snapshot.note.id: snapshot,
      };
      final encryptedPrivateEntries = <PreparedEncryptedPrivateSyncNote>[];
      for (final rawEntry
          in (decoded['encryptedPrivateNotes'] as List<dynamic>? ??
              const <dynamic>[])) {
        final entry = PreparedEncryptedPrivateSyncNote.fromJson(rawEntry);
        if (entry == null) {
          throw const SyncSafetyException('sync.error.malformed_private_note');
        }
        final localPending = localPrivatePendingById[entry.note.id];
        if (localPending != null &&
            !pendingPrivateChangeMatchesRemote(localPending, entry)) {
          throw const SyncSafetyException('sync.error.private_note_conflict');
        }
        encryptedPrivateEntries.add(entry);
      }
      for (final rawProfiles
          in (decoded['privateProfiles'] as List<dynamic>? ??
              const <dynamic>[])) {
        await ref
            .read(privateMemoProfileStoreProvider)
            .importSyncPayload(rawProfiles);
      }
      final attachmentPayloads = <String, Map<String, dynamic>>{
        for (final entry
            in (decoded['attachments'] as List<dynamic>? ?? const <dynamic>[]))
          (entry as Map)['id'] as String: Map<String, dynamic>.from(entry),
      };
      // Shared across notes (per vault) so attachments referenced by several
      // notes are downloaded and stored once, and objects already present
      // locally are not downloaded at all.
      final storedBySyncAttachmentIdByVault = <String, Map<String, String?>>{};
      final previewBySyncAttachmentIdByVault = <String, Map<String, String?>>{};
      Future<Map<String, String?>> storedMapForVault(String vaultId) async {
        final existing = storedBySyncAttachmentIdByVault[vaultId];
        if (existing != null) {
          return existing;
        }
        final seeded = await _localAttachmentPathsByContentHash(vaultId);
        storedBySyncAttachmentIdByVault[vaultId] = seeded;
        return seeded;
      }

      // Encrypted private entries can be stored while their profile is locked.
      // Only legacy plain private entries must wait for an unlock before the
      // bundle can become the replay anchor.
      final lockedPrivateVaultIds = <String>{};
      final lockedEncryptedPrivateVaultIds = <String>{};
      var importedEncryptedPrivateCount = 0;
      if (encryptedPrivateEntries.isNotEmpty) {
        final profileKeys = ref.read(profileDataKeyServiceProvider);
        for (final entry in encryptedPrivateEntries) {
          final remoteNote = entry.note.copyWith(
            deletedAt: entry.action == PendingNoteChangeAction.delete
                ? (entry.note.deletedAt ?? DateTime.now())
                : null,
            clearDeletedAt: entry.action == PendingNoteChangeAction.upsert,
            syncState: NoteSyncState.synced,
          );
          if (entry.action != PendingNoteChangeAction.delete &&
              await profileKeys.keyForVault(remoteNote.vaultId) == null) {
            lockedEncryptedPrivateVaultIds.add(remoteNote.vaultId);
          }
          final storedBySyncAttachmentId = await storedMapForVault(
            remoteNote.vaultId,
          );
          final previewBySyncAttachmentId = previewBySyncAttachmentIdByVault
              .putIfAbsent(remoteNote.vaultId, () => <String, String?>{});
          final importedPrivateEntry = await _importEncryptedPrivateSyncNote(
            entry: PreparedEncryptedPrivateSyncNote(
              action: entry.action,
              note: remoteNote,
              attachments: entry.attachments,
            ),
            inlinePayloads: attachmentPayloads,
            storedBySyncAttachmentId: storedBySyncAttachmentId,
            previewBySyncAttachmentId: previewBySyncAttachmentId,
          );
          final existingPrivateNote =
              existingPrivateSnapshotsById[importedPrivateEntry.note.id]?.note;
          if (existingPrivateNote != null &&
              _incomingEncryptedPrivateIsOlder(
                existingPrivateNote,
                importedPrivateEntry.note,
              )) {
            _diagnostic(
              'older encrypted private sync note skipped',
              data: {
                'noteId': importedPrivateEntry.note.id,
                'localRevision': existingPrivateNote.revision,
                'remoteRevision': importedPrivateEntry.note.revision,
              },
            );
            final existingSnapshot =
                existingPrivateSnapshotsById[importedPrivateEntry.note.id]!;
            final pendingAction = existingPrivateNote.deletedAt == null
                ? PendingNoteChangeAction.upsert
                : PendingNoteChangeAction.delete;
            final queuedNote = existingPrivateNote.copyWith(
              syncState: existingPrivateNote.deletedAt == null
                  ? NoteSyncState.pendingUpload
                  : NoteSyncState.pendingDelete,
            );
            await encryptedDatabase.upsertOne(
              note: queuedNote,
              attachments: existingSnapshot.attachments,
              pendingChange: PendingNoteChangeRecord(
                noteId: queuedNote.id,
                vaultId: queuedNote.vaultId,
                revision: queuedNote.revision,
                action: pendingAction,
                queuedAt: _encryptedSyncMoment(queuedNote),
                contentHash: queuedNote.contentHash,
                deletedAt: queuedNote.deletedAt,
              ),
            );
            existingPrivateSnapshotsById[queuedNote.id] = EncryptedNoteSnapshot(
              note: queuedNote,
              attachments: existingSnapshot.attachments,
            );
            continue;
          }
          await encryptedDatabase.upsertOne(
            note: importedPrivateEntry.note,
            attachments: importedPrivateEntry.attachments,
          );
          existingPrivateSnapshotsById[importedPrivateEntry.note.id] =
              EncryptedNoteSnapshot(
                note: importedPrivateEntry.note,
                attachments: importedPrivateEntry.attachments,
              );
          importedEncryptedPrivateCount += 1;
        }
      }
      final rawNoteEntries =
          decoded['notes'] as List<dynamic>? ?? const <dynamic>[];
      final importedChanges = <PreparedSyncNote>[];
      var importedEntryCount = 0;
      final totalEntries = rawNoteEntries.length;

      for (final rawEntry in rawNoteEntries) {
        if (importedEntryCount > 0 && importedEntryCount % 25 == 0) {
          await _yieldToUi();
        }
        importedEntryCount++;
        _setProgressDetail(
          progress: SyncTransferProgress.applyingBundle,
          detail: 'Applying note',
          completedItems: importedEntryCount - 1,
          totalItems: totalEntries,
        );
        final entry = Map<String, dynamic>.from(rawEntry as Map);
        final note = NoteEntry.fromJson(
          Map<String, dynamic>.from(entry['note'] as Map),
        );
        if (isPrivateVaultId(note.vaultId) &&
            !ref
                .read(profileDataKeyServiceProvider)
                .isProfileUnlocked(note.vaultId)) {
          lockedPrivateVaultIds.add(note.vaultId);
          continue;
        }
        final action = PendingNoteChangeAction.values.firstWhere(
          (value) => value.name == entry['action'],
          orElse: () => note.deletedAt == null
              ? PendingNoteChangeAction.upsert
              : PendingNoteChangeAction.delete,
        );
        final storedBySyncAttachmentId = await storedMapForVault(note.vaultId);
        final previewBySyncAttachmentId = previewBySyncAttachmentIdByVault
            .putIfAbsent(note.vaultId, () => <String, String?>{});

        final importedAttachments = <NoteAttachment>[];
        for (final attachment in note.attachments) {
          _setProgressDetail(
            progress: SyncTransferProgress.applyingBundle,
            detail: 'Applying attachment for note',
            completedItems: importedEntryCount - 1,
            totalItems: totalEntries,
          );
          await _yieldToUi();
          importedAttachments.add(
            await _importRemoteSyncAttachment(
              attachment: attachment,
              note: note,
              inlinePayloads: attachmentPayloads,
              storedBySyncAttachmentId: storedBySyncAttachmentId,
              previewBySyncAttachmentId: previewBySyncAttachmentId,
            ),
          );
        }
        final importedBlocks = <NoteBlock>[];
        for (final block in note.blocks) {
          final attachment = block.attachment;
          if (attachment != null) {
            _setProgressDetail(
              progress: SyncTransferProgress.applyingBundle,
              detail: 'Applying block attachment for note',
              completedItems: importedEntryCount - 1,
              totalItems: totalEntries,
            );
            await _yieldToUi();
          }
          importedBlocks.add(
            attachment == null
                ? block
                : block.copyWith(
                    attachment: await _importRemoteSyncAttachment(
                      attachment: attachment,
                      note: note,
                      inlinePayloads: attachmentPayloads,
                      storedBySyncAttachmentId: storedBySyncAttachmentId,
                      previewBySyncAttachmentId: previewBySyncAttachmentId,
                    ),
                  ),
          );
        }
        importedChanges.add(
          PreparedSyncNote(
            action: action,
            note: note.copyWith(
              attachments: importedAttachments,
              blocks: importedBlocks,
            ),
          ),
        );
      }
      if (importedChanges.isNotEmpty) {
        await ref
            .read(notesControllerProvider.notifier)
            .mergeFromSync(importedChanges);
        ref.invalidate(syncQueueSummaryProvider);
      }
      if (importedEncryptedPrivateCount > 0) {
        await ref.read(notesControllerProvider.notifier).reloadFromStorage();
        ref.invalidate(syncQueueSummaryProvider);
      }
      // A manually selected delta/new checkpoint does not prove that every
      // preceding record was applied. Only a validated walk may move past it.
      final remote = state.remoteStatus;
      final canAdvanceAnchor =
          historyValidated ||
          (remote != null &&
              remote.isFullBundle &&
              remote.replayBaseFileId == null);
      if (lockedPrivateVaultIds.isEmpty) {
        await ref
            .read(syncBundleStateStoreProvider)
            .recordApply(
              state.remoteStatus,
              coveredRemoteFileIds:
                  _coverageFromBundle(decoded)?.coveredBundleIds ?? const {},
              advanceAnchor: canAdvanceAnchor,
            );
        ref.invalidate(syncBundleStateProvider);
      }
      await _setPendingPrivateBundleApply(
        lockedPrivateVaultIds.isNotEmpty ||
            lockedEncryptedPrivateVaultIds.isNotEmpty,
      );
      state = state.copyWith(
        stage: SyncTransferStage.success,
        message:
            lockedPrivateVaultIds.isEmpty &&
                lockedEncryptedPrivateVaultIds.isEmpty
            ? 'sync.info.apply_success'
            : _privateProfileNotesPendingUnlockMessage,
      );
      await _recordSyncHistory(
        startedAt: historyStartedAt,
        operation: 'apply',
        success: true,
        message: state.message,
        queueBefore: queueBeforeApply,
        queueAfter: await _readLocalSyncQueueSummary(),
        remoteStatus: state.remoteStatus,
        localBundle: localBundle,
      );
    } on HimemoDecryptionException {
      state = state.copyWith(
        stage: SyncTransferStage.error,
        message: _syncBundleDecryptionMessage,
      );
      await _recordSyncHistory(
        startedAt: historyStartedAt,
        operation: 'apply',
        success: false,
        message: state.message,
        queueBefore: queueBeforeApply,
        remoteStatus: state.remoteStatus,
        localBundle: localBundle,
      );
    } catch (error) {
      state = state.copyWith(stage: SyncTransferStage.error, message: '$error');
      await _recordSyncHistory(
        startedAt: historyStartedAt,
        operation: 'apply',
        success: false,
        message: state.message,
        queueBefore: queueBeforeApply,
        remoteStatus: state.remoteStatus,
        localBundle: localBundle,
      );
    }
  }

  final _attachmentDownloads = <String, Future<NoteAttachment>>{};

  /// Downloads one attachment and persists only its local reference. Explicit
  /// user downloads are allowed on mobile data, including encrypted profiles.
  Future<NoteAttachment> downloadAttachment(
    NoteAttachment attachment, {
    bool force = false,
  }) async {
    await ref.read(notesControllerProvider.notifier).restoreCompleted;
    final reference = attachment.filePath;
    if (reference == null || reference.isEmpty) {
      throw const SyncSafetyException(
        'sync.error.remote_attachment_unavailable',
      );
    }
    final hash =
        syncAttachmentObjectContentHash(reference) ??
        attachment.syncAttachmentContentHash;
    if (!force && !isSyncAttachmentObjectRef(reference)) {
      final metadata = await ref
          .read(encryptedAttachmentStoreProvider)
          .storedPayloadMetadata(reference);
      if (metadata != null) {
        try {
          final bytes = await ref
              .read(encryptedAttachmentStoreProvider)
              .readAttachment(reference, type: attachment.type);
          if (bytes != null && bytes.isNotEmpty) {
            return attachment;
          }
        } catch (_) {
          // A stored container can exist while its contents are unreadable.
        }
      }
    }
    if (hash == null || hash.isEmpty) {
      throw const SyncSafetyException(
        'sync.error.remote_attachment_unavailable',
      );
    }
    final provider = ref.read(syncProviderControllerProvider);
    if (!_supportsRemoteTransport(provider)) {
      throw const SyncSafetyException('sync.error.select_target_for_download');
    }
    final owners = <NoteEntry>[];
    for (final note in ref.read(notesControllerProvider)) {
      if ([
        ...note.attachments,
        ...note.blocks.map((b) => b.attachment).nonNulls,
      ].any(
        (candidate) =>
            candidate.type == attachment.type &&
            (candidate.filePath == reference ||
                candidate.syncAttachmentContentHash == hash),
      )) {
        owners.add(note);
      }
    }
    final selectedNoteId = ref.read(selectedNoteIdProvider);
    final activeVaultId = ref.read(activeIdentityProvider);
    final owner =
        owners.where((note) => note.id == selectedNoteId).firstOrNull ??
        owners.where((note) => note.vaultId == activeVaultId).firstOrNull ??
        owners.firstOrNull;
    if (owner == null) {
      throw const SyncSafetyException('sync.error.attachment_context_changed');
    }
    final key =
        '${provider.name}:${owner.vaultId}:${attachment.type.name}:$hash:$force';
    final pending = _attachmentDownloads[key];
    if (pending != null) {
      final downloaded = await pending;
      return downloaded.copyWith(
        label: attachment.label,
        durationMs: attachment.durationMs,
        previewBytesBase64:
            attachment.previewBytesBase64 ?? downloaded.previewBytesBase64,
      );
    }
    final operation = _downloadAttachmentForNote(
      attachment,
      owner,
      provider,
      hash,
      force: force,
    );
    _attachmentDownloads[key] = operation;
    try {
      return await operation;
    } finally {
      _attachmentDownloads.remove(key);
    }
  }

  Future<NoteAttachment> _downloadAttachmentForNote(
    NoteAttachment attachment,
    NoteEntry note,
    SyncProvider provider,
    String hash, {
    bool force = false,
  }) async {
    final profileKeys = ref.read(profileDataKeyServiceProvider);
    if (await profileKeys.keyForVault(note.vaultId) == null) {
      throw const SyncSafetyException(
        'sync.error.unlock_private_profiles_before_download',
      );
    }
    final reusablePaths = force
        ? <String, String?>{}
        : await _localAttachmentPathsByContentHash(note.vaultId);
    final reusablePath = reusablePaths[hash];
    if (reusablePath != null) {
      try {
        final bytes = await ref
            .read(encryptedAttachmentStoreProvider)
            .readAttachment(reusablePath, type: attachment.type);
        if (bytes == null || bytes.isEmpty) {
          reusablePaths.remove(hash);
        }
      } catch (_) {
        reusablePaths.remove(hash);
      }
    }
    final imported = await _importRemoteSyncAttachment(
      attachment: attachment.copyWith(
        filePath: syncAttachmentObjectRef(hash),
        previewBytesBase64: force ? null : attachment.previewBytesBase64,
      ),
      note: note,
      inlinePayloads: const {},
      storedBySyncAttachmentId: reusablePaths,
      previewBySyncAttachmentId: {},
      deferOnMobile: false,
    );
    final storedPath = imported.filePath;
    if (storedPath == null || isSyncAttachmentObjectRef(storedPath)) {
      throw const SyncSafetyException(
        'sync.error.remote_attachment_unavailable',
      );
    }
    if (ref.read(syncProviderControllerProvider) != provider) {
      throw const SyncSafetyException('sync.error.attachment_context_changed');
    }
    if (await profileKeys.keyForVault(note.vaultId) == null) {
      throw const SyncSafetyException(
        'sync.error.unlock_private_profiles_before_download',
      );
    }
    // Encrypted private objects must also be readable with this profile's key
    // before replacing the remote reference or reporting success to the UI.
    final bytes = await ref
        .read(encryptedAttachmentStoreProvider)
        .readAttachment(storedPath, type: attachment.type);
    if (bytes == null || bytes.isEmpty) {
      throw const SyncSafetyException(
        'sync.error.remote_attachment_unavailable',
      );
    }
    await ref
        .read(notesControllerProvider.notifier)
        .applyDownloadedAttachment(
          vaultId: note.vaultId,
          sourceReference: attachment.filePath!,
          downloaded: imported,
          clearPreview: force,
        );
    return imported;
  }

  Future<int> downloadDeferredAttachments({String? vaultId}) async {
    if (!_supportsRemoteTransport(ref.read(syncProviderControllerProvider))) {
      return 0;
    }
    _startBusy(SyncTransferProgress.downloadingBundle);
    final provider = ref.read(syncProviderControllerProvider);
    try {
      var count = 0;
      var scannedNoteCount = 0;
      final currentNotes = ref
          .read(notesControllerProvider)
          .where((note) => vaultId == null || note.vaultId == vaultId)
          .toList(growable: false);
      final totalNotes = currentNotes.length;
      // Shared across notes (per vault) so an object referenced by several
      // notes is downloaded once and existing local files are reused.
      final storedBySyncAttachmentIdByVault = <String, Map<String, String?>>{};
      final previewBySyncAttachmentIdByVault = <String, Map<String, String?>>{};
      Future<Map<String, String?>> storedMapForVault(String vaultId) async {
        final existing = storedBySyncAttachmentIdByVault[vaultId];
        if (existing != null) {
          return existing;
        }
        final seeded = await _localAttachmentPathsByContentHash(vaultId);
        storedBySyncAttachmentIdByVault[vaultId] = seeded;
        return seeded;
      }

      for (final note in currentNotes) {
        if (scannedNoteCount > 0 && scannedNoteCount % 25 == 0) {
          await _yieldToUi();
        }
        scannedNoteCount++;
        _setProgressDetail(
          progress: SyncTransferProgress.downloadingBundle,
          detail: 'Checking attachments',
          completedItems: scannedNoteCount - 1,
          totalItems: totalNotes,
        );
        final storedBySyncAttachmentId = await storedMapForVault(note.vaultId);
        final previewBySyncAttachmentId = previewBySyncAttachmentIdByVault
            .putIfAbsent(note.vaultId, () => <String, String?>{});
        Future<NoteAttachment> hydrate(NoteAttachment attachment) async {
          final remoteRef = attachment.filePath;
          if (!isSyncAttachmentObjectRef(remoteRef)) {
            return attachment;
          }
          if (ref.read(syncProviderControllerProvider) != provider) {
            throw const SyncSafetyException(
              'sync.error.attachment_context_changed',
            );
          }
          if (await ref
                  .read(profileDataKeyServiceProvider)
                  .keyForVault(note.vaultId) ==
              null) {
            throw const SyncSafetyException(
              'sync.error.unlock_private_profiles_before_download',
            );
          }
          final imported = await _importRemoteSyncAttachment(
            attachment: attachment,
            note: note,
            inlinePayloads: const <String, Map<String, dynamic>>{},
            storedBySyncAttachmentId: storedBySyncAttachmentId,
            previewBySyncAttachmentId: previewBySyncAttachmentId,
            deferOnMobile: false,
          );
          final storedPath = imported.filePath;
          if (storedPath != null && storedPath != remoteRef) {
            if (ref.read(syncProviderControllerProvider) != provider) {
              throw const SyncSafetyException(
                'sync.error.attachment_context_changed',
              );
            }
            final bytes = await ref
                .read(encryptedAttachmentStoreProvider)
                .readAttachment(storedPath, type: attachment.type);
            if (bytes == null || bytes.isEmpty) {
              throw const SyncSafetyException(
                'sync.error.remote_attachment_unavailable',
              );
            }
            await ref
                .read(notesControllerProvider.notifier)
                .applyDownloadedAttachment(
                  vaultId: note.vaultId,
                  sourceReference: remoteRef!,
                  downloaded: imported,
                );
            count += 1;
          }
          return imported;
        }

        for (final attachment in note.attachments) {
          await hydrate(attachment);
        }
        for (final block in note.blocks) {
          if (block.attachment != null) {
            await hydrate(block.attachment!);
          }
        }
      }
      state = state.copyWith(
        stage: SyncTransferStage.success,
        message: count == 0
            ? 'sync.info.no_deferred_attachments'
            : 'sync.info.deferred_attachments_downloaded',
      );
      return count;
    } on HimemoDecryptionException {
      state = state.copyWith(
        stage: SyncTransferStage.error,
        message: _syncBundleDecryptionMessage,
      );
      rethrow;
    } catch (error) {
      state = state.copyWith(stage: SyncTransferStage.error, message: '$error');
      rethrow;
    }
  }

  Future<void> restoreUnlockedPrivateAttachments(String vaultId) async {
    final hasRemoteAttachment = ref
        .read(notesControllerProvider)
        .any(
          (note) =>
              note.vaultId == vaultId &&
              (note.attachments.any(
                    (attachment) =>
                        isSyncAttachmentObjectRef(attachment.filePath),
                  ) ||
                  note.blocks.any(
                    (block) =>
                        isSyncAttachmentObjectRef(block.attachment?.filePath),
                  )),
        );
    if (!hasRemoteAttachment) {
      return;
    }
    try {
      await downloadDeferredAttachments(vaultId: vaultId);
    } catch (error) {
      // Unlocking the profile must still succeed when an attachment is
      // temporarily unavailable. Its remote reference remains on the note.
      _diagnostic(
        'unlocked private attachment download deferred',
        data: {'vaultId': vaultId, 'error': error},
      );
    }
  }

  Future<SyncBundlePreview> previewDownloadedBundle() async {
    final localBundle = state.localBundle;
    if (localBundle == null) {
      throw StateError('sync.error.download_before_review');
    }
    try {
      final decoded = await ref
          .read(secureSyncBundleStoreProvider)
          .readBundleJson(localBundle.reference);
      if (decoded == null) {
        throw StateError('sync.error.downloaded_bundle_decryption_failed');
      }
      await _expandExcludedRemoteNotes(decoded);
      return buildSyncBundlePreview(
        decodedBundle: decoded,
        currentNotes: ref.read(notesControllerProvider),
      );
    } on HimemoDecryptionException {
      state = state.copyWith(
        stage: SyncTransferStage.error,
        message: _syncBundleDecryptionMessage,
      );
      rethrow;
    }
  }

  Future<PreparedSyncNote?> downloadLatestRemoteNoteForConflict(
    String noteId,
  ) async {
    final provider = ref.read(syncProviderControllerProvider);
    if (!_supportsRemoteTransport(provider)) {
      state = const SyncTransferState(
        stage: SyncTransferStage.error,
        message: 'sync.error.select_target_for_download',
      );
      return null;
    }
    _startBusy(SyncTransferProgress.downloadingBundle);
    try {
      final remoteBundle = await runFirebaseTrace(
        'sync_download_latest_bundle_for_conflict',
        _downloadLatestRemoteBundle,
      );
      await _storeDownloadedBundle(
        remoteBundle,
        emptyMessage: 'sync.info.no_usable_remote_bundle',
      );
      if (remoteBundle == null) {
        return null;
      }
      final localBundle = state.localBundle;
      if (localBundle == null) {
        return null;
      }
      final changes = await _readPreparedChangesFromBundle(
        localBundle.reference,
        noteId: noteId,
      );
      for (final change in changes) {
        return PreparedSyncNote(
          action: change.action,
          note: change.note.copyWith(syncState: NoteSyncState.synced),
        );
      }

      // The newest bundle can be a delta that changes another note. Walk
      // history newest-first and use the first occurrence of this note; that
      // is its effective remote version at the reviewed latest anchor.
      if (remoteBundle.status.isFullBundle) {
        return null;
      }
      final history = await runFirebaseTrace(
        'sync_list_history_for_conflict',
        () => _listReplayHistory(const SyncBundleState()),
      );
      final latestIndex = history.indexWhere(
        (status) => status.fileId == remoteBundle.status.fileId,
      );
      if (latestIndex == -1) {
        throw const SyncSafetyException('sync.error.remote_history_incomplete');
      }
      if (latestIndex > 0) {
        throw const SyncSafetyException(
          'sync.error.conflict_remote_changed_after_review',
        );
      }
      var reachedFullSnapshot = false;
      for (final status in history.skip(latestIndex + 1)) {
        final historicalBundle = await runFirebaseTrace(
          'sync_download_historical_bundle_for_conflict',
          () => _downloadRemoteBundleById(status.fileId),
        );
        if (historicalBundle == null) {
          throw const SyncSafetyException('sync.error.remote_bundle_missing');
        }
        final historicalChanges = await _readPreparedChangesFromRemotePayload(
          historicalBundle.encodedPayload,
          noteId: noteId,
        );
        if (historicalChanges.isNotEmpty) {
          final change = historicalChanges.first;
          return PreparedSyncNote(
            action: change.action,
            note: change.note.copyWith(syncState: NoteSyncState.synced),
          );
        }
        if (status.isFullBundle) {
          reachedFullSnapshot = true;
          break;
        }
      }
      if (!reachedFullSnapshot) {
        throw const SyncSafetyException('sync.error.remote_history_incomplete');
      }
      return null;
    } on HimemoDecryptionException {
      state = state.copyWith(
        stage: SyncTransferStage.error,
        message: _syncBundleDecryptionMessage,
      );
      return null;
    } catch (error) {
      state = state.copyWith(stage: SyncTransferStage.error, message: '$error');
      return null;
    }
  }

  Future<void> recordDownloadedBundleApplied() async {
    // A single-note choice is not an acknowledgement of the entire bundle.
    ref.invalidate(syncBundleStateProvider);
  }

  // Maps contentHash -> existing local attachment path for the given vault,
  // so applying a bundle reuses files that are already stored locally instead
  // of re-downloading objects shared across notes. Scoped per vault because
  // stored attachment payloads are encrypted with the vault key.
  Future<Map<String, String?>> _localAttachmentPathsByContentHash(
    String vaultId,
  ) async {
    final stored = <String, String?>{};
    final attachmentStore = ref.read(encryptedAttachmentStoreProvider);

    Future<void> consider(NoteAttachment attachment) async {
      final filePath = attachment.filePath;
      if (filePath == null ||
          filePath.isEmpty ||
          isSyncAttachmentObjectRef(filePath)) {
        return;
      }
      var hash = attachment.syncAttachmentContentHash;
      if (hash == null || hash.isEmpty) {
        // Public sync hashes are hashes of the clear payload and cannot be
        // reconstructed from the encrypted local file.  The fallback is only
        // for private notes, whose remote object hash is the encrypted
        // payload hash used by private sync.
        if (!isPrivateVaultId(vaultId)) {
          return;
        }
        final encryptedPayload = await attachmentStore.readStoredPayload(
          filePath,
        );
        if (encryptedPayload == null || encryptedPayload.isEmpty) {
          return;
        }
        hash = await _encryptedAttachmentPayloadContentHash(encryptedPayload);
      }
      if (stored.containsKey(hash)) {
        return;
      }
      if (await attachmentStore.storedPayloadMetadata(filePath) != null) {
        stored[hash] = filePath;
      }
    }

    for (final note in ref.read(notesControllerProvider)) {
      if (note.vaultId != vaultId) {
        continue;
      }
      for (final attachment in note.attachments) {
        await consider(attachment);
      }
      for (final block in note.blocks) {
        final attachment = block.attachment;
        if (attachment != null) {
          await consider(attachment);
        }
      }
    }
    return stored;
  }

  Future<NoteAttachment> _importRemoteSyncAttachment({
    required NoteAttachment attachment,
    required NoteEntry note,
    required Map<String, Map<String, dynamic>> inlinePayloads,
    required Map<String, String?> storedBySyncAttachmentId,
    required Map<String, String?> previewBySyncAttachmentId,
    bool deferOnMobile = true,
  }) async {
    final filePath = attachment.filePath;
    if (filePath == null) {
      return attachment;
    }
    if (isSyncAttachmentObjectRef(filePath)) {
      final contentHash = syncAttachmentObjectContentHash(filePath);
      if (contentHash == null) {
        return attachment.copyWith(filePath: null, previewBytesBase64: null);
      }
      final inlinePayload = inlinePayloads[contentHash];
      final hasInlinePayload =
          inlinePayload != null &&
          ((inlinePayload['bytesBase64'] as String?)?.isNotEmpty == true ||
              (inlinePayload['encryptedPayload'] as String?)?.isNotEmpty ==
                  true);
      if (inlinePayload != null && !hasInlinePayload) {
        _diagnostic(
          'remote attachment object metadata found',
          data: {
            'contentHash': contentHash,
            'type': inlinePayload['type'],
            'label': inlinePayload['label'],
          },
        );
      }
      if (inlinePayload != null && hasInlinePayload) {
        return _importInlineSyncAttachment(
          attachment: attachment,
          note: note,
          attachmentId: contentHash,
          payload: inlinePayload,
          storedBySyncAttachmentId: storedBySyncAttachmentId,
          previewBySyncAttachmentId: previewBySyncAttachmentId,
        );
      }
      final connectionKind = await ref
          .read(networkConnectionServiceProvider)
          .currentKind();
      if (deferOnMobile && connectionKind == NetworkConnectionKind.mobile) {
        _diagnostic(
          'remote attachment object deferred on mobile',
          data: {
            'contentHash': contentHash,
            'type': attachment.type.name,
            'label': attachment.label,
          },
        );
        return attachment;
      }
      if (!storedBySyncAttachmentId.containsKey(contentHash)) {
        final encodedPayload = await _downloadRemoteAttachmentObject(
          contentHash,
        );
        if (encodedPayload == null || encodedPayload.isEmpty) {
          throw const SyncSafetyException(
            'sync.error.remote_attachment_unavailable',
          );
        } else {
          final decoded = await ref
              .read(secureSyncBundleStoreProvider)
              .readAttachmentObjectPayload(encodedPayload);
          final payloadHash = decoded['contentHash'] as String? ?? contentHash;
          if (payloadHash != contentHash) {
            throw StateError('sync.error.attachment_object_hash_mismatch');
          }
          final payloadType = AttachmentType.values.firstWhere(
            (value) => value.name == decoded['type'],
            orElse: () => attachment.type,
          );
          final label = decoded['label'] as String? ?? attachment.label;
          final encryptedPayload = decoded['encryptedPayload'] as String?;
          final bytesBase64 = decoded['bytesBase64'] as String?;
          if (encryptedPayload != null && encryptedPayload.isNotEmpty) {
            if (await _encryptedAttachmentPayloadContentHash(
                  encryptedPayload,
                ) !=
                contentHash) {
              throw StateError('sync.error.attachment_object_hash_mismatch');
            }
            previewBySyncAttachmentId[contentHash] =
                attachment.previewBytesBase64;
            storedBySyncAttachmentId[contentHash] = await ref
                .read(encryptedAttachmentStoreProvider)
                .storeEncryptedPayload(
                  encodedPayload: encryptedPayload,
                  type: payloadType,
                  fileNameHint: label,
                  vaultId: note.vaultId,
                );
          } else if (bytesBase64 == null || bytesBase64.isEmpty) {
            throw const SyncSafetyException(
              'sync.error.remote_attachment_unavailable',
            );
          } else {
            final decodedBytes = await _decodeSyncAttachmentBytes(bytesBase64);
            if (decodedBytes.contentHash != contentHash) {
              throw StateError('sync.error.attachment_object_hash_mismatch');
            }
            final clearBytes = decodedBytes.bytes;
            previewBySyncAttachmentId[contentHash] =
                payloadType == AttachmentType.video
                ? await _videoPreviewBytesBase64ForBytes(
                    clearBytes,
                    label: label,
                    mimeType: 'video/mp4',
                  )
                : attachment.previewBytesBase64;
            final encryptedPayload = await ref
                .read(encryptedAttachmentStoreProvider)
                .encryptAttachmentBytes(
                  bytes: clearBytes,
                  type: payloadType,
                  vaultId: note.vaultId,
                );
            storedBySyncAttachmentId[contentHash] = await ref
                .read(encryptedAttachmentStoreProvider)
                .storeEncryptedPayload(
                  encodedPayload: encryptedPayload,
                  type: payloadType,
                  fileNameHint: label,
                  vaultId: note.vaultId,
                );
          }
        }
      }
      final storedPath = storedBySyncAttachmentId[contentHash];
      final metadata = storedPath == null
          ? null
          : await ref
                .read(encryptedAttachmentStoreProvider)
                .storedPayloadMetadata(storedPath);
      return attachment.copyWith(
        filePath: storedPath ?? attachment.filePath,
        syncAttachmentContentHash: contentHash,
        localPayloadSizeBytes: metadata?.sizeBytes,
        localPayloadModifiedAtMillis: metadata?.modifiedAtMillis,
        previewBytesBase64:
            previewBySyncAttachmentId[contentHash] ??
            attachment.previewBytesBase64,
      );
    }
    if (!filePath.startsWith('sync-attachment://')) {
      return attachment;
    }
    final attachmentId = filePath.substring('sync-attachment://'.length);
    final payload = inlinePayloads[attachmentId];
    if (payload == null) {
      return attachment.copyWith(filePath: null, previewBytesBase64: null);
    }
    return _importInlineSyncAttachment(
      attachment: attachment,
      note: note,
      attachmentId: attachmentId,
      payload: payload,
      storedBySyncAttachmentId: storedBySyncAttachmentId,
      previewBySyncAttachmentId: previewBySyncAttachmentId,
    );
  }

  Future<PreparedEncryptedPrivateSyncNote> _importEncryptedPrivateSyncNote({
    required PreparedEncryptedPrivateSyncNote entry,
    required Map<String, Map<String, dynamic>> inlinePayloads,
    required Map<String, String?> storedBySyncAttachmentId,
    required Map<String, String?> previewBySyncAttachmentId,
  }) async {
    if (entry.action == PendingNoteChangeAction.delete) {
      return entry;
    }
    final profileKey = await ref
        .read(profileDataKeyServiceProvider)
        .keyForVault(entry.note.vaultId);
    if (profileKey == null) {
      return entry;
    }
    final encryptionService = ref.read(encryptionServiceProvider);
    final payload = await encryptionService.decryptJson(
      encodedPayload: entry.note.encryptedPayload,
      secretKey: profileKey,
    );
    final decodedAttachments = <NoteAttachment>[];
    for (final attachmentRecord in entry.attachments) {
      final attachmentPayload = await encryptionService.decryptJson(
        encodedPayload: attachmentRecord.encryptedPayload,
        secretKey: profileKey,
      );
      decodedAttachments.add(NoteAttachment.fromJson(attachmentPayload));
    }
    final legacyAttachments =
        (payload['attachments'] as List<dynamic>? ?? const <dynamic>[])
            .map((raw) => Map<String, dynamic>.from(raw as Map))
            .map(NoteAttachment.fromJson)
            .toList(growable: false);
    final note =
        NoteEntry.fromJson({
          ...payload,
          'attachments':
              (decodedAttachments.isNotEmpty
                      ? decodedAttachments
                      : legacyAttachments)
                  .map((attachment) => attachment.toJson())
                  .toList(),
        }).copyWith(
          createdAt: entry.note.createdAt,
          updatedAt: entry.note.updatedAt,
          deletedAt: entry.note.deletedAt,
          isPinned: entry.note.isPinned,
          revision: entry.note.revision,
          syncState: entry.note.syncState,
          deviceId: entry.note.deviceId,
          contentHash: entry.note.contentHash,
        );

    Future<NoteAttachment> importAttachment(NoteAttachment attachment) {
      return _importRemoteSyncAttachment(
        attachment: attachment,
        note: note,
        inlinePayloads: inlinePayloads,
        storedBySyncAttachmentId: storedBySyncAttachmentId,
        previewBySyncAttachmentId: previewBySyncAttachmentId,
      );
    }

    final importedAttachments = <NoteAttachment>[];
    for (final attachment in note.attachments) {
      importedAttachments.add(await importAttachment(attachment));
    }
    final importedBlocks = <NoteBlock>[];
    for (final block in note.blocks) {
      final attachment = block.attachment;
      importedBlocks.add(
        attachment == null
            ? block
            : block.copyWith(attachment: await importAttachment(attachment)),
      );
    }
    final importedNote = note.copyWith(
      attachments: importedAttachments,
      blocks: importedBlocks,
    );
    final notePayload = Map<String, dynamic>.from(importedNote.toJson());
    notePayload['attachments'] = const <Map<String, dynamic>>[];
    final encryptedNotePayload = await encryptionService.encryptJson(
      payload: notePayload,
      secretKey: profileKey,
    );
    final importedRecords = <EncryptedAttachmentRecord>[];
    for (var i = 0; i < importedNote.attachments.length; i++) {
      importedRecords.add(
        EncryptedAttachmentRecord(
          noteId: importedNote.id,
          position: i,
          encryptedPayload: await encryptionService.encryptJson(
            payload: importedNote.attachments[i].toJson(),
            secretKey: profileKey,
          ),
        ),
      );
    }
    return PreparedEncryptedPrivateSyncNote(
      action: entry.action,
      note: EncryptedNoteRecord.fromNote(
        note: importedNote,
        encryptedPayload: encryptedNotePayload,
      ),
      attachments: importedRecords,
    );
  }

  bool _incomingEncryptedPrivateIsOlder(
    EncryptedNoteRecord current,
    EncryptedNoteRecord incoming,
  ) {
    if (incoming.revision != current.revision) {
      return incoming.revision < current.revision;
    }
    return _encryptedSyncMoment(incoming)
        .isBefore(_encryptedSyncMoment(current));
  }

  DateTime _encryptedSyncMoment(EncryptedNoteRecord note) {
    return note.deletedAt ?? note.updatedAt ?? note.createdAt;
  }

  Future<NoteAttachment> _importInlineSyncAttachment({
    required NoteAttachment attachment,
    required NoteEntry note,
    required String attachmentId,
    required Map<String, dynamic> payload,
    required Map<String, String?> storedBySyncAttachmentId,
    required Map<String, String?> previewBySyncAttachmentId,
  }) async {
    if (!storedBySyncAttachmentId.containsKey(attachmentId)) {
      final payloadType = AttachmentType.values.firstWhere(
        (value) => value.name == payload['type'],
        orElse: () => attachment.type,
      );
      final label = payload['label'] as String? ?? attachment.label;
      final bytesBase64 = payload['bytesBase64'] as String?;
      if (bytesBase64 != null && bytesBase64.isNotEmpty) {
        final decodedBytes = await _decodeSyncAttachmentBytes(bytesBase64);
        final clearBytes = decodedBytes.bytes;
        previewBySyncAttachmentId[attachmentId] =
            payloadType == AttachmentType.video
            ? await _videoPreviewBytesBase64ForBytes(
                clearBytes,
                label: label,
                mimeType: 'video/mp4',
              )
            : null;
        final encryptedPayload = await ref
            .read(encryptedAttachmentStoreProvider)
            .encryptAttachmentBytes(
              bytes: clearBytes,
              type: payloadType,
              vaultId: note.vaultId,
            );
        storedBySyncAttachmentId[attachmentId] = await ref
            .read(encryptedAttachmentStoreProvider)
            .storeEncryptedPayload(
              encodedPayload: encryptedPayload,
              type: payloadType,
              fileNameHint: label,
              vaultId: note.vaultId,
            );
      } else {
        previewBySyncAttachmentId[attachmentId] = null;
        final legacyPayload = payload['encryptedPayload'] as String?;
        storedBySyncAttachmentId[attachmentId] =
            legacyPayload == null || legacyPayload.isEmpty
            ? null
            : await ref
                  .read(encryptedAttachmentStoreProvider)
                  .storeEncryptedPayload(
                    encodedPayload: legacyPayload,
                    type: payloadType,
                    fileNameHint: label,
                    vaultId: note.vaultId,
                  );
      }
    }
    return attachment.copyWith(
      filePath: storedBySyncAttachmentId[attachmentId],
      previewBytesBase64: previewBySyncAttachmentId[attachmentId],
    );
  }

  Future<List<PreparedSyncNote>> _readPreparedChangesFromBundle(
    String reference, {
    String? noteId,
  }) async {
    final decoded = await ref
        .read(secureSyncBundleStoreProvider)
        .readBundleJson(reference);
    if (decoded == null) {
      throw StateError('sync.error.downloaded_bundle_decryption_failed');
    }
    return _readPreparedChangesFromDecodedBundle(decoded, noteId: noteId);
  }

  Future<List<PreparedSyncNote>> _readPreparedChangesFromRemotePayload(
    String encodedPayload, {
    required String noteId,
  }) async {
    final decoded = await ref
        .read(secureSyncBundleStoreProvider)
        .readRemoteBundlePayloadJson(encodedPayload);
    return _readPreparedChangesFromDecodedBundle(decoded, noteId: noteId);
  }

  Future<List<PreparedSyncNote>> _readPreparedChangesFromDecodedBundle(
    Map<String, dynamic> decoded, {
    String? noteId,
  }) async {
    await _expandExcludedRemoteNotes(decoded);
    final allRawNoteEntries =
        decoded['notes'] as List<dynamic>? ?? const <dynamic>[];
    final rawNoteEntries = noteId == null
        ? allRawNoteEntries
        : allRawNoteEntries
              .where((rawEntry) {
                final entry = Map<String, dynamic>.from(rawEntry as Map);
                final rawNote = Map<String, dynamic>.from(entry['note'] as Map);
                return rawNote['id'] == noteId;
              })
              .toList(growable: false);
    final lockedPrivateVaultIds = <String>{};
    for (final rawEntry in rawNoteEntries) {
      final entry = Map<String, dynamic>.from(rawEntry as Map);
      final note = NoteEntry.fromJson(
        Map<String, dynamic>.from(entry['note'] as Map),
      );
      if (isPrivateVaultId(note.vaultId) &&
          !ref
              .read(profileDataKeyServiceProvider)
              .isProfileUnlocked(note.vaultId)) {
        lockedPrivateVaultIds.add(note.vaultId);
      }
    }
    if (lockedPrivateVaultIds.isNotEmpty) {
      throw StateError('sync.error.private_profile_locked');
    }
    final attachmentPayloads = <String, Map<String, dynamic>>{
      for (final entry
          in (decoded['attachments'] as List<dynamic>? ?? const <dynamic>[]))
        (entry as Map)['id'] as String: Map<String, dynamic>.from(entry),
    };
    final importedChanges = <PreparedSyncNote>[];
    for (final rawEntry in rawNoteEntries) {
      final entry = Map<String, dynamic>.from(rawEntry as Map);
      final note = NoteEntry.fromJson(
        Map<String, dynamic>.from(entry['note'] as Map),
      );
      final action = PendingNoteChangeAction.values.firstWhere(
        (value) => value.name == entry['action'],
        orElse: () => note.deletedAt == null
            ? PendingNoteChangeAction.upsert
            : PendingNoteChangeAction.delete,
      );
      final storedBySyncAttachmentId = <String, String?>{};
      final previewBySyncAttachmentId = <String, String?>{};

      final importedAttachments = <NoteAttachment>[];
      for (final attachment in note.attachments) {
        importedAttachments.add(
          await _importRemoteSyncAttachment(
            attachment: attachment,
            note: note,
            inlinePayloads: attachmentPayloads,
            storedBySyncAttachmentId: storedBySyncAttachmentId,
            previewBySyncAttachmentId: previewBySyncAttachmentId,
          ),
        );
      }
      final importedBlocks = <NoteBlock>[];
      for (final block in note.blocks) {
        final attachment = block.attachment;
        importedBlocks.add(
          attachment == null
              ? block
              : block.copyWith(
                  attachment: await _importRemoteSyncAttachment(
                    attachment: attachment,
                    note: note,
                    inlinePayloads: attachmentPayloads,
                    storedBySyncAttachmentId: storedBySyncAttachmentId,
                    previewBySyncAttachmentId: previewBySyncAttachmentId,
                  ),
                ),
        );
      }
      importedChanges.add(
        PreparedSyncNote(
          action: action,
          note: note.copyWith(
            attachments: importedAttachments,
            blocks: importedBlocks,
          ),
        ),
      );
    }
    return importedChanges;
  }

  Future<void> _storeDownloadedBundle(
    DownloadedRemoteSyncBundle? remoteBundle, {
    required String emptyMessage,
  }) async {
    if (remoteBundle == null) {
      state = SyncTransferState(
        stage: SyncTransferStage.success,
        message: emptyMessage,
        remoteStatus: state.remoteStatus,
        localBundle: state.localBundle,
      );
      return;
    }
    final localBundle = await ref
        .read(secureSyncBundleStoreProvider)
        .writeEncryptedBundlePayload(
          remoteBundle.encodedPayload,
          noteCount: remoteBundle.status.noteCount ?? 0,
          attachmentCount: remoteBundle.status.attachmentCount ?? 0,
          fileNameOverride: _downloadedSyncBundleFileName,
        );
    state = SyncTransferState(
      stage: SyncTransferStage.success,
      message: 'sync.info.remote_bundle_saved_locally',
      remoteStatus: remoteBundle.status,
      localBundle: localBundle,
    );
    await ref
        .read(syncBundleStateStoreProvider)
        .recordRemoteStatus(remoteBundle.status);
  }

  Future<void> applyPendingPrivateDownloadedBundleIfNeeded() async {
    if (!await _hasPendingPrivateBundleApply()) {
      return;
    }
    try {
      if (state.localBundle == null) {
        final restored = await ref
            .read(secureSyncBundleStoreProvider)
            .readStoredEncryptedBundle(
              fileNameOverride: _downloadedSyncBundleFileName,
            );
        if (restored == null) {
          await _setPendingPrivateBundleApply(false);
          return;
        }
        state = state.copyWith(localBundle: restored);
      }
      await applyDownloadedBundle();
    } catch (error) {
      _diagnostic(
        'pending private downloaded bundle apply failed',
        data: {'error': error},
      );
    }
  }

  Future<void> _setPendingPrivateBundleApply(bool pending) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pendingPrivateBundleApplyKey, pending);
  }

  Future<bool> _hasPendingPrivateBundleApply() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_pendingPrivateBundleApplyKey) ?? false;
  }

  bool _supportsRemoteTransport(SyncProvider provider) {
    return provider == SyncProvider.googleDrive ||
        provider == SyncProvider.iCloud;
  }

  bool _remoteBundleNeedsApply(
    RemoteSyncBundleStatus remoteStatus,
    SyncBundleState bundleState,
  ) {
    return remoteBundleNeedsApplyForSync(remoteStatus, bundleState);
  }

  Future<LocalNoteArchive> _buildLocalZipArchive({
    String? password,
    Set<String>? vaultIds,
    bool includeSampleNotes = false,
  }) async {
    final exportedAt = DateTime.now();
    final notes = ref
        .read(notesControllerProvider)
        .where((entry) => entry.deletedAt == null)
        .where(
          (entry) =>
              vaultIds == null ||
              vaultIds.isEmpty ||
              vaultIds.contains(entry.vaultId),
        )
        .where((entry) => includeSampleNotes || !isGeneratedSampleNote(entry))
        .toList(growable: false);
    final archiveFiles = <_LocalArchiveFilePayload>[];
    final exportedNotes = <Map<String, dynamic>>[];
    var attachmentCount = 0;

    for (final note in notes) {
      final archivePathByAttachmentKey = <String, String>{};

      Future<NoteAttachment> exportAttachment(
        NoteAttachment attachment,
        int index,
      ) async {
        final filePath = attachment.filePath;
        if (filePath == null || filePath.isEmpty) {
          return attachment.copyWith(filePath: null, previewBytesBase64: null);
        }
        final key = _attachmentExportKey(attachment);
        final existingPath = archivePathByAttachmentKey[key];
        if (existingPath != null) {
          return attachment.copyWith(
            filePath: existingPath,
            previewBytesBase64: null,
          );
        }
        final bytes = await ref
            .read(encryptedAttachmentStoreProvider)
            .readAttachment(filePath, type: attachment.type);
        if (bytes == null || bytes.isEmpty) {
          return attachment.copyWith(filePath: null, previewBytesBase64: null);
        }
        final archivePath = _archiveAttachmentPath(
          noteId: note.id,
          index: index,
          label: attachment.label,
        );
        archiveFiles.add(
          _LocalArchiveFilePayload(
            name: archivePath,
            bytes: TransferableTypedData.fromList([
              bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
            ]),
          ),
        );
        archivePathByAttachmentKey[key] = archivePath;
        attachmentCount += 1;
        return attachment.copyWith(
          filePath: archivePath,
          previewBytesBase64: null,
        );
      }

      final exportedAttachments = <NoteAttachment>[];
      for (var i = 0; i < note.attachments.length; i++) {
        exportedAttachments.add(await exportAttachment(note.attachments[i], i));
      }
      final exportedBlocks = <NoteBlock>[];
      for (var i = 0; i < note.blocks.length; i++) {
        final block = note.blocks[i];
        final attachment = block.attachment;
        exportedBlocks.add(
          attachment == null
              ? block
              : block.copyWith(
                  attachment: await exportAttachment(
                    attachment,
                    note.attachments.length + i,
                  ),
                ),
        );
      }

      exportedNotes.add(
        note
            .copyWith(
              attachments: exportedAttachments,
              blocks: exportedBlocks,
              syncState: NoteSyncState.localOnly,
            )
            .toJson(),
      );
    }

    final manifest = {
      'format': 'org.ruhenheim.himemo.notes.zip',
      'version': 1,
      'exportedAt': exportedAt.toIso8601String(),
      'encryption': password == null || password.isEmpty
          ? 'none'
          : 'zip-aes-256',
      'noteCount': exportedNotes.length,
      'attachmentCount': attachmentCount,
      'contents': ['notes.json', 'attachments/'],
    };
    final encoded = await _encodeLocalZipArchive(
      manifest: manifest,
      notes: exportedNotes,
      files: archiveFiles,
      password: password,
    );
    if (encoded.isEmpty) {
      throw StateError('ZIP archive could not be encoded.');
    }
    return LocalNoteArchive(
      bytes: Uint8List.fromList(encoded),
      fileName: _localArchiveFileName(
        exportedAt,
        passwordProtected: password != null && password.isNotEmpty,
      ),
      noteCount: exportedNotes.length,
      attachmentCount: attachmentCount,
      isPasswordProtected: password != null && password.isNotEmpty,
    );
  }

  Future<_DecodedLocalZipArchive> _decodeLocalZipArchive(
    List<int> bytes, {
    String? password,
  }) async {
    final source = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    if (kIsWeb || source.lengthInBytes < 512 * 1024) {
      return _decodeLocalZipArchivePayloadInBackground(
        _LocalZipDecodeRequest(
          bytes: TransferableTypedData.fromList([source]),
          password: password,
        ),
      );
    }
    return Isolate.run(
      () => _decodeLocalZipArchivePayloadInBackground(
        _LocalZipDecodeRequest(
          bytes: TransferableTypedData.fromList([source]),
          password: password,
        ),
      ),
    );
  }

  Future<Uint8List> _encodeLocalZipArchive({
    required Map<String, dynamic> manifest,
    required List<Map<String, dynamic>> notes,
    required List<_LocalArchiveFilePayload> files,
    String? password,
  }) async {
    final request = _LocalZipEncodeRequest(
      manifest: manifest,
      notes: notes,
      files: files,
      password: password == null || password.isEmpty ? null : password,
    );
    if (kIsWeb) {
      final encoded = _encodeLocalZipArchivePayloadInBackground(request);
      return encoded.materialize().asUint8List();
    }
    final encoded = await Isolate.run(
      () => _encodeLocalZipArchivePayloadInBackground(request),
    );
    return encoded.materialize().asUint8List();
  }

  Map<String, dynamic> _zipArchiveAsSyncBundle(
    _DecodedLocalZipArchive archive,
  ) {
    return {
      'deviceId': 'local-zip',
      'exportedAt': archive.manifest['exportedAt'],
      'notes': [
        for (final note in archive.notes)
          {'action': PendingNoteChangeAction.upsert.name, 'note': note},
      ],
      'attachments': [
        for (final entry in archive.attachmentFiles.entries)
          {'id': entry.key, 'encryptedPayload': '', 'type': 'file'},
      ],
    };
  }

  String _attachmentExportKey(NoteAttachment attachment) {
    return [
      attachment.type.name,
      attachment.label,
      attachment.filePath ?? '',
      attachment.durationMs?.toString() ?? '',
    ].join('\u0000');
  }

  String _archiveAttachmentPath({
    required String noteId,
    required int index,
    required String label,
  }) {
    final rawName = path.basename(label).trim();
    final safeName = _safeArchiveSegment(
      rawName.isEmpty ? 'attachment.bin' : rawName,
    );
    return 'attachments/${_safeArchiveSegment(noteId)}_${index}_$safeName';
  }

  String _safeArchiveSegment(String value) {
    final safe = value
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return safe.isEmpty ? 'file' : safe;
  }

  String _localArchiveFileName(
    DateTime exportedAt, {
    required bool passwordProtected,
  }) {
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp =
        '${exportedAt.year}${two(exportedAt.month)}${two(exportedAt.day)}_${two(exportedAt.hour)}${two(exportedAt.minute)}${two(exportedAt.second)}';
    final suffix = passwordProtected ? 'encrypted' : 'plain';
    return 'himemo_archive_${suffix}_$stamp.zip';
  }

  Future<RemoteSyncBundleStatus?> _fetchLatestRemoteStatus() {
    final provider = ref.read(syncProviderControllerProvider);
    return switch (provider) {
      SyncProvider.iCloud =>
        ref.read(iCloudSyncTransportProvider).fetchLatestBundleStatus(),
      SyncProvider.googleDrive => _withGoogleDriveAuthRecovery(
        () => ref
            .read(googleDriveSyncTransportProvider)
            .fetchLatestBundleStatus(),
      ),
      SyncProvider.off => Future.value(null),
    };
  }

  Future<void> _refreshRemoteStatusInBackground() async {
    try {
      final provider = ref.read(syncProviderControllerProvider);
      final remoteStatus = await _fetchLatestRemoteStatus();
      _cacheRemoteStatus(provider, remoteStatus);
      if (remoteStatus != null) {
        await ref
            .read(syncBundleStateStoreProvider)
            .recordRemoteStatus(remoteStatus);
        state = state.copyWith(remoteStatus: remoteStatus);
      }
    } catch (_) {
      _diagnostic('background remote status refresh failed');
    }
  }

  Future<List<RemoteSyncBundleStatus>> _listRemoteHistory({int limit = 10}) {
    final provider = ref.read(syncProviderControllerProvider);
    return switch (provider) {
      SyncProvider.iCloud =>
        ref.read(iCloudSyncTransportProvider).listBundleHistory(limit: limit),
      SyncProvider.googleDrive => _withGoogleDriveAuthRecovery(
        () => ref
            .read(googleDriveSyncTransportProvider)
            .listBundleHistory(limit: limit),
      ),
      SyncProvider.off => Future.value(const <RemoteSyncBundleStatus>[]),
    };
  }

  Future<RemoteSyncBundleStatus> _uploadRemoteBundle({
    required String encodedPayload,
    required String deviceId,
    required int noteCount,
    required int attachmentCount,
    required String bundleKind,
    String? replayBaseFileId,
  }) {
    final provider = ref.read(syncProviderControllerProvider);
    return switch (provider) {
      SyncProvider.iCloud =>
        ref
            .read(iCloudSyncTransportProvider)
            .uploadBundle(
              encodedPayload: encodedPayload,
              deviceId: deviceId,
              noteCount: noteCount,
              attachmentCount: attachmentCount,
              bundleKind: bundleKind,
              replayBaseFileId: replayBaseFileId,
            ),
      SyncProvider.googleDrive => _withGoogleDriveAuthRecovery(
        () => ref
            .read(googleDriveSyncTransportProvider)
            .uploadBundle(
              encodedPayload: encodedPayload,
              deviceId: deviceId,
              noteCount: noteCount,
              attachmentCount: attachmentCount,
              bundleKind: bundleKind,
              replayBaseFileId: replayBaseFileId,
            ),
      ),
      SyncProvider.off => Future.error(
        StateError('Remote sync is not enabled.'),
      ),
    };
  }

  RemoteAttachmentMaintenanceTransport? _managedAttachmentTransport() {
    final provider = ref.read(syncProviderControllerProvider);
    final Object? transport = switch (provider) {
      SyncProvider.googleDrive => ref.read(googleDriveSyncTransportProvider),
      SyncProvider.iCloud => ref.read(iCloudSyncTransportProvider),
      SyncProvider.off => null,
    };
    return transport is RemoteAttachmentMaintenanceTransport ? transport : null;
  }

  SyncUploadReservations _uploadReservations() => SyncUploadReservations(
    'sync.upload_reservations.${ref.read(syncProviderControllerProvider).name}.v1',
  );

  Future<void> _finishAttachmentReservation(
    String uploadId,
    String bundleId,
  ) async {
    final transport = _managedAttachmentTransport();
    if (transport == null) return;
    await _uploadReservations().published(uploadId, bundleId);
    for (final id in _pinnedAttachmentIds[uploadId] ?? const <String>{}) {
      await transport.releaseAttachmentObject(
        recordId: id,
        uploadId: uploadId,
        publishedBundleId: bundleId,
      );
    }
    _pinnedAttachmentIds.remove(uploadId);
    await _uploadReservations().finish(uploadId);
  }

  SyncUploadReceiptCache _uploadReceiptCache() => SyncUploadReceiptCache(
    'sync.upload_receipts.${ref.read(syncProviderControllerProvider).name}.v1',
  );

  Future<Map<String, String>> _publishedUploadReceipts(
    List<RemoteSyncBundleStatus> history, {
    List<ManagedAttachmentObject>? inventory,
  }) async {
    final managed = _managedAttachmentTransport();
    if (managed == null) return {};
    final active = {
      for (final item
          in inventory ?? await managed.listManagedAttachmentObjects())
        ...item.uploadIds,
    };
    if (active.isEmpty) return {};
    final cache = _uploadReceiptCache();
    var cached = <String, Map<String, String>>{};
    try {
      cached = await cache.readBundles();
    } catch (_) {
      _diagnostic('publication receipt cache read deferred');
    }
    final additions = <String, Map<String, String>>{};
    final receipts = <String, String>{};
    for (final status in history) {
      var extracted = cached[status.fileId];
      if (extracted == null) {
        final decoded = await _readRemoteBundleJsonById(status.fileId);
        extracted = <String, String>{};
        final uploadId = decoded['uploadId'];
        if (uploadId is String && uploadId.isNotEmpty) {
          extracted[uploadId] = status.fileId;
        }
        final prior = decoded['uploadReceipts'];
        if (prior is Map) {
          for (final entry in prior.entries) {
            if (entry.key is String &&
                (entry.key as String).isNotEmpty &&
                entry.value is String &&
                (entry.value as String).isNotEmpty) {
              extracted.putIfAbsent(
                entry.key as String,
                () => entry.value as String,
              );
            }
          }
        }
        // Empty results are cached too: unknown reservations must not force
        // repeated downloads of every immutable historical payload.
        additions[status.fileId] = extracted;
      }
      for (final entry in extracted.entries) {
        if (active.contains(entry.key)) {
          receipts.putIfAbsent(entry.key, () => entry.value);
        }
      }
    }
    try {
      if (additions.isNotEmpty) await cache.writeBundles(additions);
      await cache.retainBundles(history.map((item) => item.fileId).toSet());
    } catch (_) {
      // A cache failure must not block sync or change reservation safety.
      _diagnostic('publication receipt cache persistence deferred');
    }
    return receipts;
  }

  Future<void> _recoverAttachmentReservations() async {
    final transport = _managedAttachmentTransport();
    if (transport == null) return;
    final pending = await _uploadReservations().read();
    final items = await transport.listManagedAttachmentObjects();
    final held = {for (final item in items) ...item.uploadIds};
    final publications = held.isEmpty
        ? <String, String>{}
        : await _publishedUploadReceipts(
            await _listReplayHistory(const SyncBundleState()),
            inventory: items,
          );
    for (final entry in pending.entries) {
      if (entry.value != null) publications[entry.key] = entry.value!;
    }
    // Any updated device may release a proven publication's holds. Receipts
    // survive compaction while holds exist, including after the origin device
    // lost its response or was uninstalled. Unknown outcomes stay reserved.
    for (final item in items) {
      for (final uploadId in item.uploadIds) {
        if (publications[uploadId] case final bundleId?) {
          await transport.releaseAttachmentObject(
            recordId: item.id,
            uploadId: uploadId,
            publishedBundleId: bundleId,
          );
        }
      }
    }
    for (final entry in pending.entries) {
      if (!held.contains(entry.key) || publications.containsKey(entry.key)) {
        await _uploadReservations().finish(entry.key);
      }
    }
  }

  Future<void> _uploadRemoteAttachmentObjects(
    List<PreparedSyncAttachment> attachments, {
    String? uploadId,
    Set<String> referencedHashes = const <String>{},
  }) async {
    final managed = _managedAttachmentTransport();
    if (managed != null && uploadId != null) {
      final byHash = {for (final item in attachments) item.contentHash: item};
      final hashes = {...referencedHashes, ...byHash.keys};
      for (final hash in hashes) {
        final item = byHash[hash];
        final payload = item != null && _preparedSyncAttachmentHasPayload(item)
            ? await ref
                  .read(secureSyncBundleStoreProvider)
                  .writeAttachmentObjectPayload(item)
            : null;
        final recordId = await managed.pinAttachmentObject(
          contentHash: hash,
          uploadId: uploadId,
          encodedPayload: payload,
          type: item?.type.name ?? 'file',
          label: item?.label ?? hash,
          sizeBytes: item?.sizeBytes ?? 0,
        );
        (_pinnedAttachmentIds[uploadId] ??= <String>{}).add(recordId);
        await _yieldToUi();
      }
      return;
    }
    if (attachments.isEmpty) {
      return;
    }
    final metadataOnly = <String>{
      for (final attachment in attachments)
        if (!_preparedSyncAttachmentHasPayload(attachment) &&
            attachment.contentHash.isNotEmpty)
          attachment.contentHash,
    };
    final uploadableAttachments = attachments
        .where(_preparedSyncAttachmentHasPayload)
        .toList(growable: false);
    final uniqueAttachments = <String, PreparedSyncAttachment>{};
    for (final attachment in uploadableAttachments) {
      uniqueAttachments.putIfAbsent(attachment.contentHash, () => attachment);
    }
    final unique = uniqueAttachments.values.toList(growable: false);
    final totalBytes = unique.fold<int>(
      0,
      (total, attachment) => total + attachment.sizeBytes,
    );
    _diagnostic(
      'attachment object upload start',
      data: {
        'requested': uploadableAttachments.length,
        'metadataOnly': attachments.length - uploadableAttachments.length,
        'unique': unique.length,
        'bytes': totalBytes,
      },
    );
    final existingHashes = await _listExistingRemoteAttachmentHashes();
    if (existingHashes == null) {
      // Older transports may not support listing object hashes.  Metadata
      // references still need an existence check; silently publishing a
      // bundle that points at a missing cloud-only object leaves an
      // unrecoverable attachment on the next device.
      for (final contentHash in metadataOnly) {
        final encodedPayload = await _downloadRemoteAttachmentObject(
          contentHash,
        );
        if (encodedPayload == null || encodedPayload.isEmpty) {
          throw StateError(
            'sync.error.remote_attachment_missing contentHash=$contentHash',
          );
        }
      }
    }
    if (uploadableAttachments.isEmpty) {
      return;
    }
    final pendingUploads = existingHashes == null
        ? unique
        : unique
              .where(
                (attachment) =>
                    !existingHashes.contains(attachment.contentHash),
              )
              .toList(growable: false);
    final skipped = unique.length - pendingUploads.length;
    _setProgressDetail(
      progress: SyncTransferProgress.uploadingBundle,
      detail: 'Checking attachment objects',
      completedItems: skipped,
      totalItems: unique.length,
    );
    await _yieldToUi();
    if (existingHashes != null) {
      _diagnostic(
        'attachment object upload existing checked',
        data: {
          'remoteKnown': existingHashes.length,
          'skipped': skipped,
          'pending': pendingUploads.length,
        },
      );
    }
    if (pendingUploads.isEmpty) {
      _setProgressDetail(
        progress: SyncTransferProgress.uploadingBundle,
        detail: 'Attachments already uploaded',
        completedItems: unique.length,
        totalItems: unique.length,
      );
      await _yieldToUi();
      _diagnostic(
        'attachment object upload progress',
        data: {
          'uploaded': unique.length,
          'total': unique.length,
          'skipped': skipped,
        },
      );
      return;
    }
    final bundleStore = ref.read(secureSyncBundleStoreProvider);
    const maxConcurrentAttachmentUploads = 1;
    var uploaded = 0;
    var nextUploadIndex = 0;
    _setProgressDetail(
      progress: SyncTransferProgress.uploadingBundle,
      detail: 'Uploading attachment',
      completedItems: skipped,
      totalItems: unique.length,
    );
    await _yieldToUi();

    Future<void> uploadWorker() async {
      while (true) {
        if (nextUploadIndex >= pendingUploads.length) {
          return;
        }
        final attachment = pendingUploads[nextUploadIndex];
        nextUploadIndex += 1;
        final encodedPayload = await bundleStore.writeAttachmentObjectPayload(
          attachment,
        );
        await _uploadRemoteAttachmentObject(
          contentHash: attachment.contentHash,
          encodedPayload: encodedPayload,
          type: attachment.type.name,
          label: attachment.label,
          sizeBytes: attachment.sizeBytes,
          skipExistingCheck: existingHashes != null,
        );
        uploaded += 1;
        final completed = skipped + uploaded;
        _setProgressDetail(
          progress: SyncTransferProgress.uploadingBundle,
          detail: 'Uploaded attachment',
          completedItems: completed,
          totalItems: unique.length,
        );
        await _yieldToUi();
        if (completed % 5 == 0 || completed == unique.length) {
          _diagnostic(
            'attachment object upload progress',
            data: {
              'uploaded': completed,
              'total': unique.length,
              'skipped': skipped,
            },
          );
        }
      }
    }

    final workerCount = math.min(
      maxConcurrentAttachmentUploads,
      pendingUploads.length,
    );
    await Future.wait([for (var i = 0; i < workerCount; i++) uploadWorker()]);
  }

  Future<Set<String>?> _listExistingRemoteAttachmentHashes() async {
    final provider = ref.read(syncProviderControllerProvider);
    switch (provider) {
      case SyncProvider.googleDrive:
        return _withGoogleDriveAuthRecovery(
          () => ref
              .read(googleDriveSyncTransportProvider)
              .listAttachmentObjectContentHashes(),
        );
      case SyncProvider.iCloud:
        try {
          return await ref
              .read(iCloudSyncTransportProvider)
              .listAttachmentObjectContentHashes();
        } catch (error) {
          // Fall back to per-object existence checks when the batch listing
          // is unavailable (e.g. older native binary without the method).
          _diagnostic(
            'icloud attachment hash listing failed',
            data: {'error': error},
          );
          return null;
        }
      case SyncProvider.off:
        return null;
    }
  }

  Future<void> _uploadRemoteAttachmentObject({
    required String contentHash,
    required String encodedPayload,
    required String type,
    required String label,
    required int sizeBytes,
    bool skipExistingCheck = false,
  }) {
    final provider = ref.read(syncProviderControllerProvider);
    return switch (provider) {
      SyncProvider.googleDrive => _withGoogleDriveAuthRecovery(
        () => ref
            .read(googleDriveSyncTransportProvider)
            .uploadAttachmentObject(
              contentHash: contentHash,
              encodedPayload: encodedPayload,
              type: type,
              label: label,
              sizeBytes: sizeBytes,
              skipExistingCheck: skipExistingCheck,
            ),
      ),
      SyncProvider.iCloud =>
        ref
            .read(iCloudSyncTransportProvider)
            .uploadAttachmentObject(
              contentHash: contentHash,
              encodedPayload: encodedPayload,
              type: type,
              label: label,
              sizeBytes: sizeBytes,
              skipExistingCheck: skipExistingCheck,
            ),
      SyncProvider.off => Future<void>.value(),
    };
  }

  Future<String?> _downloadRemoteAttachmentObject(String contentHash) async {
    final provider = ref.read(syncProviderControllerProvider);
    Future<String?> download() => switch (provider) {
      SyncProvider.googleDrive => _withGoogleDriveAuthRecovery(
        () => ref
            .read(googleDriveSyncTransportProvider)
            .downloadAttachmentObject(contentHash),
      ),
      SyncProvider.iCloud =>
        ref
            .read(iCloudSyncTransportProvider)
            .downloadAttachmentObject(contentHash),
      SyncProvider.off => Future<String?>.value(),
    };
    var encodedPayload = await download();
    if ((encodedPayload == null || encodedPayload.isEmpty) &&
        provider == SyncProvider.iCloud) {
      for (final delay in const [
        Duration(milliseconds: 700),
        Duration(seconds: 2),
        Duration(seconds: 4),
      ]) {
        await Future<void>.delayed(delay);
        encodedPayload = await download();
        if (encodedPayload != null && encodedPayload.isNotEmpty) {
          break;
        }
      }
    }
    if (encodedPayload == null || encodedPayload.isEmpty) {
      _diagnostic(
        'remote attachment object unavailable',
        data: {'provider': provider.name, 'contentHash': contentHash},
      );
    }
    return encodedPayload;
  }

  Future<DownloadedRemoteSyncBundle?> _downloadLatestRemoteBundle() {
    final provider = ref.read(syncProviderControllerProvider);
    return switch (provider) {
      SyncProvider.iCloud =>
        ref.read(iCloudSyncTransportProvider).downloadLatestBundle(),
      SyncProvider.googleDrive => _withGoogleDriveAuthRecovery(
        () => ref.read(googleDriveSyncTransportProvider).downloadLatestBundle(),
      ),
      SyncProvider.off => Future.value(null),
    };
  }

  Future<DownloadedRemoteSyncBundle?> _downloadRemoteBundleById(String id) {
    final provider = ref.read(syncProviderControllerProvider);
    return switch (provider) {
      SyncProvider.iCloud =>
        ref.read(iCloudSyncTransportProvider).downloadBundleByRecordName(id),
      SyncProvider.googleDrive => _withGoogleDriveAuthRecovery(
        () => ref
            .read(googleDriveSyncTransportProvider)
            .downloadBundleByFileId(id),
      ),
      SyncProvider.off => Future.value(null),
    };
  }

  Future<T> _withGoogleDriveAuthRecovery<T>(
    Future<T> Function() operation,
  ) async {
    try {
      await _ensureGoogleDriveSyncKeyReady();
      return await operation();
    } catch (error, stackTrace) {
      if (!_isRecoverableGoogleDriveAuthorizationError(error)) {
        rethrow;
      }
      final authController = ref.read(syncAuthControllerProvider.notifier);
      await authController.connect(SyncProvider.googleDrive);
      if (!authController.stateFor(SyncProvider.googleDrive).isAuthenticated) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      await ref
          .read(syncProviderControllerProvider.notifier)
          .prepareGoogleDriveSyncKeyAfterAuthentication(
            accountId: authController.stateFor(SyncProvider.googleDrive).userId,
            force: true,
          );
      return await operation();
    }
  }

  Future<void> _ensureGoogleDriveSyncKeyReady() async {
    final authController = ref.read(syncAuthControllerProvider.notifier);
    var authState = authController.stateFor(SyncProvider.googleDrive);
    if (!authState.isAuthenticated) {
      await authController.connect(SyncProvider.googleDrive);
      authState = authController.stateFor(SyncProvider.googleDrive);
    }
    if (!authState.isAuthenticated) {
      throw StateError(
        authState.message ?? 'Google Drive authentication is required.',
      );
    }
    await ref
        .read(syncProviderControllerProvider.notifier)
        .prepareGoogleDriveSyncKeyAfterAuthentication(
          accountId: authState.userId,
        );
  }

  bool _isRecoverableGoogleDriveAuthorizationError(Object error) {
    return error is GoogleDriveAuthConfigurationException &&
        error.message.contains('Google Drive authorization is not available');
  }

  SyncTransferState _failureState(
    Object error, {
    RemoteSyncBundleStatus? remoteStatus,
    StoredSyncBundle? localBundle,
  }) {
    if (error is HimemoDecryptionException) {
      return SyncTransferState(
        stage: SyncTransferStage.error,
        message: _syncBundleDecryptionMessage,
        remoteStatus: remoteStatus,
        localBundle: localBundle,
      );
    }
    if (error is StateError &&
        error.message == 'Sync bundle key is not available.') {
      final provider = ref.read(syncProviderControllerProvider);
      return SyncTransferState(
        stage: SyncTransferStage.error,
        message: provider == SyncProvider.iCloud
            ? _iCloudSyncBundleKeyWaitingMessage
            : _syncBundleKeyMissingMessage,
        remoteStatus: remoteStatus,
        localBundle: localBundle,
      );
    }
    if (error is GoogleDriveSyncException) {
      final retryAfter = error.retryAfter;
      if (retryAfter != null) {
        _scheduleCooldownRefresh(retryAfter);
      }
      return SyncTransferState(
        stage: SyncTransferStage.error,
        message: error.message,
        remoteStatus: remoteStatus,
        localBundle: localBundle,
        cooldownUntil: retryAfter == null
            ? null
            : DateTime.now().add(retryAfter),
      );
    }
    if (error is ICloudSyncException) {
      final retryAfter = error.retryAfter;
      if (retryAfter != null) {
        _scheduleCooldownRefresh(retryAfter);
      }
      return SyncTransferState(
        stage: SyncTransferStage.error,
        message: error.message,
        remoteStatus: remoteStatus,
        localBundle: localBundle,
        cooldownUntil: retryAfter == null
            ? null
            : DateTime.now().add(retryAfter),
      );
    }
    return SyncTransferState(
      stage: SyncTransferStage.error,
      message: '$error',
      remoteStatus: remoteStatus,
      localBundle: localBundle,
    );
  }

  void _scheduleCooldownRefresh(Duration duration) {
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer(duration, () {
      state = state.copyWith(clearCooldown: true);
    });
  }
}

final syncAuthControllerProvider =
    NotifierProvider<SyncAuthController, Map<SyncProvider, SyncAuthState>>(
      SyncAuthController.new,
    );

class SyncAuthController extends Notifier<Map<SyncProvider, SyncAuthState>> {
  static const _storageKey = 'sync.auth_accounts.v1';
  static const _integrityApprovalKey = 'sync.integrity_approved.v1';
  static const _googleScopes = <String>[
    'https://www.googleapis.com/auth/drive.appdata',
  ];
  bool _restored = false;

  @override
  Map<SyncProvider, SyncAuthState> build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return {
      for (final provider in SyncProvider.values)
        provider: SyncAuthState.idle(provider),
    };
  }

  SyncAuthState stateFor(SyncProvider provider) =>
      state[provider] ?? SyncAuthState.idle(provider);

  Future<void> connectSelected() async {
    await connect(ref.read(syncProviderControllerProvider));
  }

  Future<void> connect(SyncProvider provider) async {
    if (provider == SyncProvider.off) {
      _update(provider, SyncAuthState.idle(provider));
      return;
    }

    _update(
      provider,
      stateFor(provider)
          .copyWith(stage: SyncAuthStage.busy, clearMessage: true),
    );

    final requiresIntegrity = provider == SyncProvider.googleDrive;
    final alreadyApproved =
        !requiresIntegrity || await _hasIntegrityApproval(provider);
    if (!alreadyApproved) {
      final verification = await ref
          .read(playIntegrityVerifierProvider)
          .verifyOperation(
            flavor: ref.read(currentAppFlavorProvider),
            operation: 'sync.enable',
            payload: {'provider': provider.name},
          );
      if (!verification.allowed) {
        _update(
          provider,
          stateFor(
            provider,
          ).copyWith(stage: SyncAuthStage.error, message: verification.message),
        );
        return;
      }
      await _markIntegrityApproved(provider);
    }

    var next = await ref.read(syncAuthGatewayProvider).connect(provider);
    next = await _prepareGoogleDriveKeyIfAuthenticated(next);

    _update(provider, next);
    await _persist();
  }

  Future<void> completeGoogleDriveWebAuthentication(
    GoogleSignInAccount account,
  ) async {
    const provider = SyncProvider.googleDrive;
    _update(
      provider,
      stateFor(provider).copyWith(
        stage: SyncAuthStage.busy,
        userId: account.id,
        displayName: account.displayName,
        email: account.email,
        clearMessage: true,
      ),
    );

    try {
      final alreadyApproved = await _hasIntegrityApproval(provider);
      if (!alreadyApproved) {
        final verification = await ref
            .read(playIntegrityVerifierProvider)
            .verifyOperation(
              flavor: ref.read(currentAppFlavorProvider),
              operation: 'sync.enable',
              payload: {'provider': provider.name},
            );
        if (!verification.allowed) {
          _update(
            provider,
            stateFor(provider).copyWith(
              stage: SyncAuthStage.error,
              message: verification.message,
            ),
          );
          return;
        }
        await _markIntegrityApproved(provider);
      }

      final authorizationClient = account.authorizationClient;
      final existingAuthorization = await authorizationClient
          .authorizationForScopes(_googleScopes);
      if (existingAuthorization == null) {
        await authorizationClient.authorizeScopes(_googleScopes);
      }

      final next = await _prepareGoogleDriveKeyIfAuthenticated(
        SyncAuthState(
          provider: provider,
          stage: SyncAuthStage.authenticated,
          userId: account.id,
          displayName: account.displayName,
          email: account.email,
          message: 'Google Drive app-data access is authorized.',
        ),
      );
      _update(provider, next);
      await _persist();
    } on GoogleSignInException catch (error) {
      _update(
        provider,
        stateFor(provider).copyWith(
          stage: SyncAuthStage.error,
          message: DefaultSyncAuthGateway()._googleDriveSignInExceptionMessage(
            error,
          ),
        ),
      );
    } catch (error) {
      _update(
        provider,
        stateFor(provider)
            .copyWith(stage: SyncAuthStage.error, message: '$error'),
      );
    }
  }

  Future<void> disconnectSelected() async {
    await disconnect(ref.read(syncProviderControllerProvider));
  }

  Future<void> disconnect(SyncProvider provider) async {
    await ref.read(syncAuthGatewayProvider).disconnect(provider);
    if (provider == SyncProvider.googleDrive) {
      ref
          .read(syncProviderControllerProvider.notifier)
          .markGoogleDriveSyncKeyPending();
    }
    _update(provider, SyncAuthState.idle(provider));
    await _persist();
  }

  Future<SyncAuthState> _prepareGoogleDriveKeyIfAuthenticated(
    SyncAuthState next,
  ) async {
    if (next.provider != SyncProvider.googleDrive || !next.isAuthenticated) {
      return next;
    }
    try {
      await ref
          .read(syncProviderControllerProvider.notifier)
          .prepareGoogleDriveSyncKeyAfterAuthentication(
            accountId: next.userId,
            force: true,
          );
      return next;
    } catch (error) {
      return next.copyWith(stage: SyncAuthStage.error, message: '$error');
    }
  }

  void _update(SyncProvider provider, SyncAuthState next) {
    state = {...state, provider: next};
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_storageKey);
      if (stored == null || stored.isEmpty) {
        return;
      }
      final decoded = Map<String, dynamic>.from(
        jsonDecode(stored) as Map<String, dynamic>,
      );
      state = {
        for (final provider in SyncProvider.values)
          provider: _normalizeRestoredState(
            provider,
            decoded[provider.name] == null
                ? SyncAuthState.idle(provider)
                : SyncAuthState.fromJson(
                    Map<String, dynamic>.from(decoded[provider.name] as Map),
                  ),
          ),
      };
    } catch (_) {
      // Invalid persisted authentication state falls back to idle states.
    }
  }

  SyncAuthState _normalizeRestoredState(
    SyncProvider provider,
    SyncAuthState restored,
  ) {
    if (provider != SyncProvider.iCloud) {
      return restored;
    }
    final message = restored.message ?? '';
    final staleAppleSignInError =
        restored.stage == SyncAuthStage.error &&
        (message.contains('SignInWithAppleAuthorizationException') ||
            message.contains(
              'com.apple.AuthenticationServices.AuthorizationError',
            ));
    if (staleAppleSignInError) {
      return SyncAuthState.idle(provider);
    }
    return restored;
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode({
        for (final entry in state.entries) entry.key.name: entry.value.toJson(),
      });
      await prefs.setString(_storageKey, encoded);
    } catch (_) {
      logDiagnostic('sync', 'provider authentication state persistence failed');
    }
  }

  Future<bool> _hasIntegrityApproval(SyncProvider provider) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_integrityApprovalKey.${provider.name}') ?? false;
  }

  Future<void> _markIntegrityApproved(SyncProvider provider) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_integrityApprovalKey.${provider.name}', true);
  }
}

final syncProviderControllerProvider =
    NotifierProvider<SyncProviderController, SyncProvider>(
      SyncProviderController.new,
    );

class SyncProviderController extends Notifier<SyncProvider> {
  static const _storageKey = 'settings.sync_provider';
  static const _googleDriveAccountBindingPrefix =
      'security.sync_bundle.google_account.v1.';
  bool _restored = false;
  String? _preparedGoogleDriveAccountId;
  Future<void>? _googleDriveKeyPreparation;

  @override
  SyncProvider build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return SyncProvider.off;
  }

  Future<void> setProvider(SyncProvider provider) async {
    if (provider == SyncProvider.iCloud && !isICloudSyncSupported) {
      provider = SyncProvider.off;
    }
    final previous = state;
    String? carriedBackupCode;
    if (provider == SyncProvider.googleDrive &&
        previous != SyncProvider.googleDrive) {
      carriedBackupCode = await _syncBundleKeyServiceFor(previous)
          .exportExistingBackupCode();
    }
    state = provider;
    if (provider != previous) {
      _preparedGoogleDriveAccountId = null;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, provider.name);
    } catch (_) {
      logDiagnostic('sync', 'provider preference persistence failed');
    }
    if (provider == SyncProvider.googleDrive &&
        carriedBackupCode != null &&
        carriedBackupCode.isNotEmpty) {
      try {
        // Moving from iCloud to Google Drive changes the secure-store source.
        // Carry the existing key locally now; Drive is contacted only after
        // Google authentication succeeds.
        await _syncBundleKeyServiceFor(SyncProvider.googleDrive)
            .importBackupCode(carriedBackupCode);
      } catch (_) {
        state = previous;
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_storageKey, previous.name);
        } catch (_) {
          logDiagnostic(
            'sync',
            'provider rollback preference persistence failed',
          );
        }
        rethrow;
      }
    }
    if (provider != SyncProvider.off && provider != previous) {
      await ref
          .read(notesControllerProvider.notifier)
          .queueCurrentStateForSync();
      ref.invalidate(syncQueueSummaryProvider);
    }
  }

  Future<void> prepareGoogleDriveSyncKeyAfterAuthentication({
    String? accountId,
    bool force = false,
  }) async {
    if (state != SyncProvider.googleDrive) {
      throw StateError('Select Google Drive before connecting an account.');
    }
    final resolvedAccountId =
        (accountId ??
                ref
                    .read(syncAuthControllerProvider.notifier)
                    .stateFor(SyncProvider.googleDrive)
                    .userId ??
                '')
            .trim();
    if (resolvedAccountId.isEmpty) {
      throw StateError('Google Drive authentication is required for sync.');
    }
    if (!force && _preparedGoogleDriveAccountId == resolvedAccountId) {
      return;
    }

    final pending = _googleDriveKeyPreparation;
    if (pending != null) {
      await pending;
      if (!force && _preparedGoogleDriveAccountId == resolvedAccountId) {
        return;
      }
    }

    final preparation = _prepareGoogleDriveSyncKey(resolvedAccountId);
    _googleDriveKeyPreparation = preparation;
    try {
      await preparation;
      _preparedGoogleDriveAccountId = resolvedAccountId;
    } finally {
      if (identical(_googleDriveKeyPreparation, preparation)) {
        _googleDriveKeyPreparation = null;
      }
    }
  }

  void markGoogleDriveSyncKeyPending() {
    _preparedGoogleDriveAccountId = null;
  }

  Future<void> _prepareGoogleDriveSyncKey(String accountId) async {
    final cloudStore = ref.read(googleDriveCloudSyncBundleKeyStoreProvider);
    final keyService = _syncBundleKeyServiceFor(SyncProvider.googleDrive);
    final legacyBackupCodes = await cloudStore.readBackupCodes();
    final localBackupCode = await keyService.exportExistingBackupCode();

    if (legacyBackupCodes.isNotEmpty) {
      final remoteBackupCode = legacyBackupCodes.first;
      for (final duplicateCode in legacyBackupCodes.skip(1)) {
        if (!keyService.backupCodesMatch(remoteBackupCode, duplicateCode)) {
          throw StateError(
            'Google Drive contains conflicting legacy recovery keys. No key was deleted; resolve the account data before syncing.',
          );
        }
      }
      if (localBackupCode != null &&
          !keyService.backupCodesMatch(localBackupCode, remoteBackupCode)) {
        throw StateError(
          'Google Drive uses a different sync recovery key. Import the matching recovery key before enabling sync.',
        );
      }
      // One-time compatibility migration: persist the legacy key locally
      // before removing every raw copy from Drive.
      await keyService.importBackupCode(remoteBackupCode);
      await cloudStore.deleteBackupCode();
      await _bindGoogleDriveAccount(accountId, keyService);
      return;
    }

    final localFingerprint = await keyService.existingFullFingerprint();
    final boundFingerprint = await _readGoogleDriveAccountBinding(accountId);
    if (localFingerprint != null && boundFingerprint == localFingerprint) {
      return;
    }

    final transport = ref.read(googleDriveSyncTransportProvider);
    final remoteBundleStatus = await transport.fetchLatestBundleStatus();
    final remoteAttachmentHashes = await transport
        .listAttachmentObjectContentHashes();
    final hasRemoteEncryptedData =
        remoteBundleStatus != null || remoteAttachmentHashes.isNotEmpty;

    if (localFingerprint == null && hasRemoteEncryptedData) {
      throw StateError(
        'Google Drive already contains encrypted data. Import its recovery key before enabling sync.',
      );
    }

    if (localFingerprint == null) {
      await keyService.obtainOrCreate();
      await _bindGoogleDriveAccount(accountId, keyService);
      return;
    }

    if (!hasRemoteEncryptedData) {
      await _bindGoogleDriveAccount(accountId, keyService);
      return;
    }

    // A local key imported on a new device is not trusted for this account
    // until it successfully authenticates an existing remote payload.
    String? validationPayload;
    if (remoteBundleStatus != null) {
      validationPayload =
          (await transport.downloadLatestBundle())?.encodedPayload;
    } else if (remoteAttachmentHashes.isNotEmpty) {
      validationPayload = await transport.downloadAttachmentObject(
        remoteAttachmentHashes.first,
      );
    }
    if (validationPayload == null || validationPayload.isEmpty) {
      throw StateError(
        'Google Drive encrypted data could not be validated with the imported recovery key.',
      );
    }
    await SecureSyncBundleStore(
      encryptionService: ref.read(encryptionServiceProvider),
      syncBundleKeyService: keyService,
    ).validateRemotePayloadWithSyncKey(validationPayload);
    await _bindGoogleDriveAccount(accountId, keyService);
  }

  SyncBundleKeyService _syncBundleKeyServiceFor(SyncProvider provider) =>
      ref.read(syncBundleKeyServiceForProvider(provider));

  String _googleDriveAccountBindingKey(String accountId) {
    final accountHash = sha256.convert(utf8.encode(accountId)).toString();
    return '$_googleDriveAccountBindingPrefix$accountHash';
  }

  Future<String?> _readGoogleDriveAccountBinding(String accountId) {
    return ref
        .read(secureKeyValueStoreProvider)
        .read(_googleDriveAccountBindingKey(accountId));
  }

  Future<void> _bindGoogleDriveAccount(
    String accountId,
    SyncBundleKeyService keyService,
  ) async {
    await ref
        .read(secureKeyValueStoreProvider)
        .write(
          _googleDriveAccountBindingKey(accountId),
          await keyService.fullFingerprint(),
        );
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_storageKey);
      if (stored == null || !ref.mounted) {
        return;
      }
      final restored = SyncProvider.values.firstWhere(
        (provider) => provider.name == stored,
        orElse: () => SyncProvider.off,
      );
      state = restored == SyncProvider.iCloud && !isICloudSyncSupported
          ? SyncProvider.off
          : restored;
      _preparedGoogleDriveAccountId = null;
    } catch (_) {
      if (ref.mounted) {
        state = SyncProvider.off;
      }
    }
  }
}
