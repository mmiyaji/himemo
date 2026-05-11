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
  return const SyncConflictAssessment(
    hasConflict: true,
    message: 'sync.error.conflict_pending_remote_newer',
  );
}
