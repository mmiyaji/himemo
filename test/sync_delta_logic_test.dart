import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/sync/data/google_drive_sync_transport.dart';
import 'package:himemo/features/sync/data/sync_bundle_state_store.dart';
import 'package:himemo/features/sync/data/sync_conflict_policy.dart';
import 'package:shared_preferences/shared_preferences.dart';

RemoteSyncBundleStatus _status(
  String fileId, {
  String? bundleKind,
  DateTime? modifiedAt,
}) {
  return RemoteSyncBundleStatus(
    fileId: fileId,
    fileName: '$fileId.enc',
    modifiedAt: modifiedAt,
    bundleKind: bundleKind,
  );
}

void main() {
  group('selectRemoteBundlesToApply', () {
    test('returns nothing for empty history', () {
      expect(
        selectRemoteBundlesToApply(
          history: const [],
          bundleState: const SyncBundleState(),
        ),
        isEmpty,
      );
    });

    test('applies every bundle newer than the applied anchor, oldest first',
        () {
      final history = [
        _status('d4', bundleKind: SyncBundleKind.delta),
        _status('d3', bundleKind: SyncBundleKind.delta),
        _status('d2', bundleKind: SyncBundleKind.delta),
        _status('f1', bundleKind: SyncBundleKind.full),
      ];
      final selected = selectRemoteBundlesToApply(
        history: history,
        bundleState: const SyncBundleState(lastAppliedRemoteFileId: 'd2'),
      );
      expect(
        selected.map((status) => status.fileId).toList(),
        ['d3', 'd4'],
      );
    });

    test('returns nothing when the anchor is already the newest bundle', () {
      final history = [
        _status('d2', bundleKind: SyncBundleKind.delta),
        _status('f1', bundleKind: SyncBundleKind.full),
      ];
      final selected = selectRemoteBundlesToApply(
        history: history,
        bundleState: const SyncBundleState(lastAppliedRemoteFileId: 'd2'),
      );
      expect(selected, isEmpty);
    });

    test('replays from the newest full snapshot when the anchor is unknown',
        () {
      final history = [
        _status('d5', bundleKind: SyncBundleKind.delta),
        _status('f4', bundleKind: SyncBundleKind.full),
        _status('d3', bundleKind: SyncBundleKind.delta),
        _status('f2', bundleKind: SyncBundleKind.full),
        _status('d1', bundleKind: SyncBundleKind.delta),
      ];
      final selected = selectRemoteBundlesToApply(
        history: history,
        bundleState: const SyncBundleState(),
      );
      expect(
        selected.map((status) => status.fileId).toList(),
        ['f4', 'd5'],
      );
    });

    test(
        'replays from the newest full snapshot when the anchor was pruned '
        'from history', () {
      final history = [
        _status('d6', bundleKind: SyncBundleKind.delta),
        _status('f5', bundleKind: SyncBundleKind.full),
      ];
      final selected = selectRemoteBundlesToApply(
        history: history,
        bundleState:
            const SyncBundleState(lastAppliedRemoteFileId: 'gone-bundle'),
      );
      expect(
        selected.map((status) => status.fileId).toList(),
        ['f5', 'd6'],
      );
    });

    test('treats legacy bundles without a kind as full snapshots', () {
      final history = [
        _status('d3', bundleKind: SyncBundleKind.delta),
        _status('legacy2'),
        _status('d1', bundleKind: SyncBundleKind.delta),
      ];
      final selected = selectRemoteBundlesToApply(
        history: history,
        bundleState: const SyncBundleState(),
      );
      expect(
        selected.map((status) => status.fileId).toList(),
        ['legacy2', 'd3'],
      );
    });

    test('replays the entire history when no full snapshot is visible', () {
      final history = [
        _status('d3', bundleKind: SyncBundleKind.delta),
        _status('d2', bundleKind: SyncBundleKind.delta),
        _status('d1', bundleKind: SyncBundleKind.delta),
      ];
      final selected = selectRemoteBundlesToApply(
        history: history,
        bundleState: const SyncBundleState(),
      );
      expect(
        selected.map((status) => status.fileId).toList(),
        ['d1', 'd2', 'd3'],
      );
    });
  });

  group('SyncBundleStateStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(const {});
    });

    test('recordUpload advances the applied anchor and delta counter',
        () async {
      final store = SyncBundleStateStore();
      await store.recordUpload(
        _status('f1', modifiedAt: DateTime.utc(2026, 6, 1)),
        fullSnapshot: true,
      );
      var state = await store.read();
      expect(state.lastAppliedRemoteFileId, 'f1');
      expect(state.lastFullUploadedAt, isNotNull);
      expect(state.deltaUploadsSinceFull, 0);

      await store.recordUpload(
        _status('d2', modifiedAt: DateTime.utc(2026, 6, 2)),
        fullSnapshot: false,
      );
      await store.recordUpload(
        _status('d3', modifiedAt: DateTime.utc(2026, 6, 3)),
        fullSnapshot: false,
      );
      state = await store.read();
      expect(state.lastAppliedRemoteFileId, 'd3');
      expect(state.deltaUploadsSinceFull, 2);

      await store.recordUpload(
        _status('f4', modifiedAt: DateTime.utc(2026, 6, 4)),
        fullSnapshot: true,
      );
      state = await store.read();
      expect(state.deltaUploadsSinceFull, 0);
    });

    test('recordApply advances the applied anchor, status checks do not',
        () async {
      final store = SyncBundleStateStore();
      await store.recordRemoteStatus(
        _status('seen-only', modifiedAt: DateTime.utc(2026, 6, 1)),
      );
      var state = await store.read();
      expect(state.lastRemoteFileId, 'seen-only');
      expect(state.lastAppliedRemoteFileId, isNull);

      await store.recordApply(
        _status('applied', modifiedAt: DateTime.utc(2026, 6, 2)),
      );
      state = await store.read();
      expect(state.lastAppliedRemoteFileId, 'applied');
      expect(state.lastAppliedAt, isNotNull);
    });

    test('state survives a JSON round trip', () async {
      final original = SyncBundleState(
        lastRemoteFileId: 'r1',
        lastRemoteModifiedAt: DateTime.utc(2026, 6, 1),
        lastRemoteDeviceId: 'device-a',
        lastUploadedAt: DateTime.utc(2026, 6, 2),
        lastAppliedAt: DateTime.utc(2026, 6, 3),
        lastAppliedRemoteFileId: 'a1',
        lastAppliedRemoteModifiedAt: DateTime.utc(2026, 6, 4),
        lastFullUploadedAt: DateTime.utc(2026, 6, 5),
        deltaUploadsSinceFull: 7,
      );
      final restored = SyncBundleState.fromJson(original.toJson());
      expect(restored.lastRemoteFileId, original.lastRemoteFileId);
      expect(restored.lastAppliedRemoteFileId, original.lastAppliedRemoteFileId);
      expect(
        restored.lastAppliedRemoteModifiedAt,
        original.lastAppliedRemoteModifiedAt,
      );
      expect(restored.lastFullUploadedAt, original.lastFullUploadedAt);
      expect(restored.deltaUploadsSinceFull, original.deltaUploadsSinceFull);
    });
  });
}
