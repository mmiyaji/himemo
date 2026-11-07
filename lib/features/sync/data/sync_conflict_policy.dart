import 'google_drive_sync_transport.dart';
import 'sync_bundle_state_store.dart';
import 'sync_bundle_coverage.dart';
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
  required bool cloudSyncSelected,
}) {
  if (!cloudSyncSelected ||
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
///   from remote history), a full snapshot supplies the base. New snapshots
///   declare their covered remote ID, so concurrent records published between
///   that base and the snapshot are also replayed.
/// - If no full snapshot is visible either, the entire available history is
///   replayed as a best effort. Per-note revision checks in the merge layer
///   make re-applying old bundles safe.
List<RemoteSyncBundleStatus> selectRemoteBundlesToApply({
  required List<RemoteSyncBundleStatus> history,
  required SyncBundleState bundleState,
  SyncBundleCoverage? coverage,
  String? coverageBundleId,
}) {
  if (history.isEmpty) {
    return const <RemoteSyncBundleStatus>[];
  }
  final appliedIds = bundleState.appliedRemoteFileIds;
  if (coverage != null && coverageBundleId != null) {
    final checkpointIndex = history.indexWhere(
      (item) => item.fileId == coverageBundleId,
    );
    final checkpoint = checkpointIndex < 0 ? null : history[checkpointIndex];
    if (checkpoint != null && checkpoint.isFullBundle) {
      if (appliedIds?.contains(checkpoint.fileId) == true) {
        return history
            .where((item) => !appliedIds!.contains(item.fileId))
            .toList()
            .reversed
            .toList();
      }
      final uncovered = history
          .where(
            (item) =>
                item.fileId != coverageBundleId &&
                !(appliedIds?.contains(item.fileId) ?? false) &&
                !coverage.coveredBundleIds.contains(item.fileId),
          )
          .toList(growable: false)
          .reversed;
      return <RemoteSyncBundleStatus>[checkpoint, ...uncovered];
    }
  }
  if (appliedIds != null) {
    return history
        .where((status) => !appliedIds.contains(status.fileId))
        .toList(growable: false)
        .reversed
        .toList(growable: false);
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
  final full = history[newestFullIndex];
  // New snapshots declare the last remote record included locally. A device
  // can publish between that base and this snapshot; replay those intervening
  // records too, even though they sort older than the full snapshot.
  final base = full.replayBaseFileId;
  final baseIndex = base == null
      ? newestFullIndex + 1
      : history.indexWhere((status) => status.fileId == base);
  final end = base == null
      ? newestFullIndex + 1
      : baseIndex < 0
      ? history.length
      : baseIndex;
  return history.sublist(0, end).reversed.toList(growable: false);
}

/// Returns whether [history] contains a trustworthy starting point for a
/// delta replay: either the device's applied anchor or a full snapshot.
bool remoteHistoryHasSafeReplayBase({
  required List<RemoteSyncBundleStatus> history,
  required SyncBundleState bundleState,
}) {
  if (history.isEmpty) {
    return false;
  }
  final anchorFileId = bundleState.lastAppliedRemoteFileId;
  if (anchorFileId != null &&
      anchorFileId.isNotEmpty &&
      history.any((status) => status.fileId == anchorFileId)) {
    return true;
  }
  return history.any((status) => status.isFullBundle);
}
