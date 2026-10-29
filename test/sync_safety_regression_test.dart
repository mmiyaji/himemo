import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:himemo/features/sync/data/google_drive_sync_transport.dart';
import 'package:himemo/features/sync/data/icloud_sync_transport.dart';
import 'package:himemo/features/sync/data/sync_bundle_state_store.dart';
import 'package:himemo/features/sync/data/sync_conflict_policy.dart';
import 'package:himemo/features/sync/data/sync_history_reader.dart';

RemoteSyncBundleStatus bundle(String id, {bool full = false, String? base}) =>
    RemoteSyncBundleStatus(
      fileId: id,
      fileName: '$id.enc',
      bundleKind: full ? SyncBundleKind.full : SyncBundleKind.delta,
      replayBaseFileId: base,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('new-device replay includes a delta published before a concurrent full snapshot', () {
    final history = [
      bundle('full-A', full: true, base: 'base'),
      bundle('concurrent-B'),
      bundle('base', full: true),
    ];
    expect(
      selectRemoteBundlesToApply(
        history: history,
        bundleState: const SyncBundleState(),
      ).map((item) => item.fileId),
      ['concurrent-B', 'full-A'],
    );
  });

  test('pruned full base still replays retained concurrent changes', () {
    final history = [
      bundle('later'),
      bundle('full-A', full: true, base: 'pruned'),
      bundle('concurrent-B'),
    ];
    expect(
      selectRemoteBundlesToApply(
        history: history,
        bundleState: const SyncBundleState(),
      ).map((item) => item.fileId),
      ['concurrent-B', 'full-A', 'later'],
    );
  });

  test(
    'history expands beyond fifty deltas until a complete base is found',
    () async {
      final history = [
        for (var i = 120; i > 0; i--) bundle('delta-$i'),
        bundle('full', full: true),
      ];
      final limits = <int>[];
      final result = await readSyncReplayHistory(
        fetch: (limit) async {
          limits.add(limit);
          return history.take(limit).toList();
        },
        applied: const SyncBundleState(),
      );
      expect(limits, [50, 100, 200]);
      expect(result.length, 121);
      expect(
        remoteHistoryHasSafeReplayBase(
          history: result,
          bundleState: const SyncBundleState(),
        ),
        isTrue,
      );
    },
  );

  test(
    'a root full snapshot cannot truncate concurrent first uploads',
    () async {
      final history = [
        bundle('root-full', full: true, base: '__root__'),
        for (var i = 70; i > 0; i--) bundle('delta-$i'),
      ];
      final limits = <int>[];
      final result = await readSyncReplayHistory(
        fetch: (limit) async {
          limits.add(limit);
          return history.take(limit).toList();
        },
        applied: const SyncBundleState(),
      );
      expect(limits, [50, 100]);
      expect(
        selectRemoteBundlesToApply(
          history: result,
          bundleState: const SyncBundleState(),
        ).length,
        71,
      );
    },
  );

  test('exhausted delta-only history stays explicitly unrecoverable', () async {
    final result = await readSyncReplayHistory(
      fetch: (limit) async => [bundle('delta')],
      applied: const SyncBundleState(),
    );
    expect(
      remoteHistoryHasSafeReplayBase(
        history: result,
        bundleState: const SyncBundleState(),
      ),
      isFalse,
    );
  });

  test('publishing preserves the applied anchor and remembers the own upload separately', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncBundleStateStore();
    await store.recordApply(bundle('base'));
    await store.recordUpload(bundle('mine', full: true, base: 'base'));
    final state = await store.read();
    expect(state.lastAppliedRemoteFileId, 'base');
    expect(state.lastUploadedRemoteFileId, 'mine');
  });

  test('iCloud cleanup skips when another device has published and never sweeps objects', () async {
    final transport = InMemoryICloudSyncTransport();
    Future<RemoteSyncBundleStatus> publish(String device) =>
        transport.uploadBundle(
          encodedPayload: device,
          deviceId: device,
          noteCount: 1,
          attachmentCount: 0,
        );
    final old = await publish('old');
    final mine = await publish('mine');
    await transport.uploadAttachmentObject(
      contentHash: 'in-flight',
      encodedPayload: 'secret',
      type: 'file',
      label: 'file',
      sizeBytes: 6,
    );
    final concurrent = await publish('other');
    final skipped = await transport.pruneObsoleteData(
      referencedAttachmentHashes: {},
      bundleFileIdsToDelete: {old.fileId},
      expectedLatestFileId: mine.fileId,
    );
    expect(skipped.deletedBundleCount, 0);
    final removed = await transport.pruneObsoleteData(
      referencedAttachmentHashes: {},
      bundleFileIdsToDelete: {old.fileId, concurrent.fileId},
      expectedLatestFileId: concurrent.fileId,
    );
    expect(removed.deletedBundleCount, 1);
    expect(
      await transport.downloadBundleByRecordName(concurrent.fileId),
      isNotNull,
    );
    expect(await transport.downloadAttachmentObject('in-flight'), 'secret');
  });
}
