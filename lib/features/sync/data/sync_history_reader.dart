import 'google_drive_sync_transport.dart';
import 'sync_bundle_state_store.dart';

/// Expands history until the applied anchor or the full snapshot's covered
/// base is visible. A root snapshot covers no older records, so it needs the
/// complete retained history to include concurrent first-device uploads.
Future<List<RemoteSyncBundleStatus>> readSyncReplayHistory({
  required Future<List<RemoteSyncBundleStatus>> Function(int limit) fetch,
  required SyncBundleState applied,
  bool requireComplete = false,
  int initialLimit = 50,
}) async {
  var limit = initialLimit;
  while (true) {
    final history = await fetch(limit);
    final anchor = applied.lastAppliedRemoteFileId;
    final anchorFound =
        anchor != null && history.any((item) => item.fileId == anchor);
    final fullIndex = history.indexWhere((item) => item.isFullBundle);
    final full = fullIndex < 0 ? null : history[fullIndex];
    final base = full?.replayBaseFileId;
    final fullBaseFound =
        full != null &&
        (base == null || history.any((item) => item.fileId == base));
    if (history.length < limit ||
        (!requireComplete && (anchorFound || fullBaseFound))) {
      return history;
    }
    limit *= 2;
  }
}
