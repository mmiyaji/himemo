import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:himemo/features/sync/data/google_drive_sync_transport.dart';
import 'package:himemo/features/sync/data/sync_bundle_coverage.dart';
import 'package:himemo/features/sync/data/sync_bundle_state_store.dart';
import 'package:himemo/features/sync/data/sync_conflict_policy.dart';

RemoteSyncBundleStatus _bundle(String id, {bool full = false}) =>
    RemoteSyncBundleStatus(
      fileId: id,
      fileName: '$id.enc',
      modifiedAt: DateTime.utc(2026, 1, 1),
      bundleKind: full ? SyncBundleKind.full : SyncBundleKind.delta,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ID set selects unseen old record despite a matching current head', () {
    final state = SyncBundleState(appliedRemoteFileIds: {'head'});
    expect(
      selectRemoteBundlesToApply(
        history: [_bundle('head'), _bundle('older')],
        bundleState: state,
      ).map((item) => item.fileId),
      ['older'],
    );
  });

  test('manifest checkpoint bootstraps without timestamp cutoffs', () {
    final selected = selectRemoteBundlesToApply(
      history: [
        _bundle('newer'),
        _bundle('checkpoint', full: true),
        _bundle('old'),
      ],
      bundleState: const SyncBundleState(),
      coverage: SyncBundleCoverage(coveredBundleIds: {'old'}),
      coverageBundleId: 'checkpoint',
    );
    expect(selected.map((item) => item.fileId), ['checkpoint', 'newer']);
  });

  test('malformed coverage manifest is rejected', () {
    expect(
      SyncBundleCoverage.tryParse({'version': 2, 'coveredBundleIds': []}),
      isNull,
    );
    expect(
      SyncBundleCoverage.tryParse({
        'version': 1,
        'coveredBundleIds': ['x', 2],
      }),
      isNull,
    );
  });

  test('serialized concurrent acknowledgements retain every ID', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncBundleStateStore();
    await Future.wait([
      store.recordApply(_bundle('a')),
      store.recordApply(_bundle('b')),
      store.recordApply(_bundle('c')),
    ]);
    expect((await store.read()).appliedRemoteFileIds, {'a', 'b', 'c'});
  });

  test('upload ID becomes known without moving applied anchor', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncBundleStateStore();
    await store.recordApply(_bundle('base'));
    await store.recordUpload(_bundle('own'));
    final state = await store.read();
    expect(state.lastAppliedRemoteFileId, 'base');
    expect(state.appliedRemoteFileIds, {'base', 'own'});
  });
}
