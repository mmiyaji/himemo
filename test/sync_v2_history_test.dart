import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/sync/data/sync_v2_history.dart';

SyncV2Change _change(
  String id, {
  Set<String> parents = const {},
  String profileId = 'profile',
  String noteId = 'note',
  bool delete = false,
  String? digest,
}) => SyncV2Change(
  id: id,
  profileId: profileId,
  noteId: noteId,
  parentIds: parents,
  operation: delete ? SyncV2Operation.delete : SyncV2Operation.upsert,
  payloadDigest: delete ? null : digest ?? 'digest-$id',
);

void main() {
  test('edit and delete remain heads until resolved in either order', () {
    final root = _change('root');
    final edit = _change('edit', parents: {'root'});
    final deletion = _change('delete', parents: {'root'}, delete: true);
    final resolution = _change(
      'resolution',
      parents: {'edit', 'delete'},
      delete: true,
    );

    expect(resolveSyncV2History([deletion, edit, root]).headIds, {
      'edit',
      'delete',
    });
    for (final history in [
      [
        root,
        edit,
        deletion,
        resolution,
        _change('edit', parents: {'root'}),
      ],
      [resolution, deletion, edit, root],
    ]) {
      final result = resolveSyncV2History(history);
      expect(result.headIds, {'resolution'});
      expect(result.pendingIds, isEmpty);
    }
  });

  test('missing ancestry leaves existing heads intact until it arrives', () {
    final root = _change('root');
    final edit = _change('edit', parents: {'root'});
    final late = _change('late', parents: {'root'});
    final merge = _change('merge', parents: {'edit', 'late'});
    final child = _change('child', parents: {'merge'});

    final incomplete = resolveSyncV2History([child, merge, edit, root]);
    expect(incomplete.headIds, {'edit'});
    expect(incomplete.pendingIds, {'merge', 'child'});
    expect(resolveSyncV2History([child, merge, edit, root, late]).headIds, {
      'child',
    });
  });

  test('rejects divergent IDs, cross-profile ancestry and cycles', () {
    for (final history in [
      [_change('a'), _change('a', digest: 'different')],
      [
        _change('a'),
        _change('b', parents: {'a'}, profileId: 'other'),
      ],
      [
        _change('a', parents: {'b'}),
        _change('b', parents: {'a'}),
      ],
    ]) {
      expect(() => resolveSyncV2History(history), throwsFormatException);
    }
  });
}
