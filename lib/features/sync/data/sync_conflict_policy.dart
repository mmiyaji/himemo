import 'google_drive_sync_transport.dart';
import 'sync_bundle_state_store.dart';
import 'sync_engine.dart';

class SyncConflictAssessment {
  const SyncConflictAssessment({required this.hasConflict, this.message});

  const SyncConflictAssessment.clear() : this(hasConflict: false);

  final bool hasConflict;
  final String? message;
}

SyncConflictAssessment assessSyncConflict({
  required SyncQueueSummary? queue,
  required RemoteSyncBundleStatus? remoteStatus,
  required SyncBundleState? bundleState,
  required bool googleDriveSelected,
}) {
  if (!googleDriveSelected ||
      queue == null ||
      remoteStatus == null ||
      bundleState == null ||
      !queue.hasPendingChanges ||
      remoteStatus.modifiedAt == null) {
    return const SyncConflictAssessment.clear();
  }

  final knownMoment = bundleState.lastAppliedAt ?? bundleState.lastUploadedAt;
  final remoteModifiedAt = remoteStatus.modifiedAt?.toUtc();
  if (knownMoment == null ||
      remoteModifiedAt == null ||
      !remoteModifiedAt.isAfter(knownMoment.toUtc())) {
    return const SyncConflictAssessment.clear();
  }
  final lastQueuedAt = queue.lastQueuedAt?.toUtc();
  if (lastQueuedAt != null && !remoteModifiedAt.isAfter(lastQueuedAt)) {
    return const SyncConflictAssessment.clear();
  }
  return const SyncConflictAssessment(
    hasConflict: true,
    message: 'sync.error.conflict_pending_remote_newer',
  );
}

/// Decides which remote bundles must be applied locally, oldest first.
///
/// [history] is the remote bundle history sorted newest-first (the order the
/// transports return). With delta bundles, skipping an intermediate bundle
/// would permanently drop the notes it carried, so:
///
/// - If the locally applied anchor ([SyncBundleState.lastAppliedRemoteFileId])
///   is found in the history, every bundle newer than it is returned.
/// - If the anchor is unknown (first sync, or the anchor bundle was pruned
///   from remote history), replay starts from the newest full snapshot, which
///   by definition contains every note; the deltas after it complete the
///   picture.
/// - If no full snapshot is visible either, the entire available history is
///   replayed as a best effort. Per-note revision checks in the merge layer
///   make re-applying old bundles safe.
List<RemoteSyncBundleStatus> selectRemoteBundlesToApply({
  required List<RemoteSyncBundleStatus> history,
  required SyncBundleState bundleState,
}) {
  if (history.isEmpty) {
    return const <RemoteSyncBundleStatus>[];
  }
  final anchorFileId = bundleState.lastAppliedRemoteFileId;
  if (anchorFileId != null && anchorFileId.isNotEmpty) {
    final anchorIndex = history.indexWhere(
      (status) => status.fileId == anchorFileId,
    );
    if (anchorIndex != -1) {
      return history.sublist(0, anchorIndex).reversed.toList(growable: false);
    }
  }
  final newestFullIndex = history.indexWhere((status) => status.isFullBundle);
  if (newestFullIndex == -1) {
    return history.reversed.toList(growable: false);
  }
  return history
      .sublist(0, newestFullIndex + 1)
      .reversed
      .toList(growable: false);
}
