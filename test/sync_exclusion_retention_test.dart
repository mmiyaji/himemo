import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/sync/data/sync_exclusion_retention.dart';

void main() {
  group('SyncExclusionRetention', () {
    test('round trips sorted IDs and rejects malformed manifests', () {
      const retention = SyncExclusionRetention(
        excludedNoteIds: {'z', 'a'},
        retainedBundleIds: {'bundle-2', 'bundle-1'},
        noteBundleIds: {'a': 'bundle-1'},
      );
      expect(
        SyncExclusionRetention.fromJson(retention.toJson())!.excludedNoteIds,
        {'a', 'z'},
      );
      expect(
        SyncExclusionRetention.fromJson(retention.toJson())!.noteBundleIds,
        {'a': 'bundle-1'},
      );
      expect(SyncExclusionRetention.fromJson({'excludedNoteIds': []}), isNull);
      expect(
        SyncExclusionRetention.fromJson({
          'excludedNoteIds': ['x', 'x'],
          'retainedBundleIds': [],
        }),
        isNull,
      );
      expect(
        SyncExclusionRetention.fromJson({
          'excludedNoteIds': ['x'],
          'retainedBundleIds': ['bundle'],
          'noteBundleIds': {'x': 'missing-bundle'},
        }),
        isNull,
      );
    });

    test('malformed historical records stop retention preparation', () {
      for (final notes in [
        42,
        [null],
        [
          {'note': 4},
        ],
        [
          {
            'note': {'id': 'recoverable'},
          },
        ],
      ]) {
        final builder = SyncExclusionRetentionBuilder(
          localExcludedNoteIds: const {},
          isExcluded: (_) => false,
        );
        expect(
          () =>
              builder.addBundle(fileId: 'only-copy', payload: {'notes': notes}),
          throwsFormatException,
        );
      }
    });

    test('retains source bundle for latest excluded state by revision', () {
      final builder = SyncExclusionRetentionBuilder(
        localExcludedNoteIds: const {},
        isExcluded: (note) => note.tags.contains('private-sync-excluded'),
      );
      builder.addBundle(
        fileId: 'old',
        modifiedAt: DateTime.utc(2025),
        payload: {
          'notes': [
            _record('n1', revision: 8, tags: ['private-sync-excluded']),
          ],
        },
      );
      builder.addBundle(
        fileId: 'new',
        modifiedAt: DateTime.utc(2024),
        payload: {
          'notes': [
            _record('n1', revision: 9, tags: ['private-sync-excluded']),
          ],
        },
      );

      final result = builder.finish();
      expect(result.excludedNoteIds, {'n1'});
      expect(result.retainedBundleIds, {'new'});
      expect(result.noteBundleIds, {'n1': 'new'});
    });

    test('preserves conflicting maximal versions but deduplicates identical copies', () {
      final builder = SyncExclusionRetentionBuilder(
        localExcludedNoteIds: const {'n1'},
        isExcluded: (_) => false,
      );
      Map<String, dynamic> change(String body) {
        final value = _record('n1', revision: 9);
        (value['note'] as Map)['body'] = body;
        return value;
      }

      builder.addBundle(
        fileId: 'a',
        payload: {
          'notes': [change('version A')],
        },
        modifiedAt: DateTime.utc(2026, 1, 1),
      );
      builder.addBundle(
        fileId: 'b',
        payload: {
          'notes': [change('version B')],
        },
        modifiedAt: DateTime.utc(2026, 1, 2),
      );
      builder.addBundle(
        fileId: 'a-copy',
        payload: {
          'notes': [change('version A')],
        },
        modifiedAt: DateTime.utc(2026, 1, 3),
      );
      expect(builder.finish().retainedBundleIds, {'b', 'a-copy'});
      expect(builder.finish().noteBundleIds, {'n1': 'a-copy'});
    });

    test('uses effective moment then remote modified time and bundle ID', () {
      final builder = SyncExclusionRetentionBuilder(
        localExcludedNoteIds: const {'n1'},
        isExcluded: (_) => false,
      );
      builder.addBundle(
        fileId: 'a',
        modifiedAt: DateTime.utc(2025, 1),
        payload: {
          'notes': [
            _record('n1', revision: 2, updatedAt: '2025-01-01T00:00:00.000Z'),
          ],
        },
      );
      builder.addBundle(
        fileId: 'z',
        modifiedAt: DateTime.utc(2025, 1),
        payload: {
          'notes': [
            _record('n1', revision: 2, updatedAt: '2025-01-01T00:00:00.000Z'),
          ],
        },
      );
      expect(builder.finish().retainedBundleIds, {'z'});
    });

    test('does not carry forward an exclusion cleared by the latest state', () {
      final builder = SyncExclusionRetentionBuilder(
        localExcludedNoteIds: const {},
        isExcluded: (note) => note.tags.contains('private-sync-excluded'),
      );
      builder.addBundle(
        fileId: 'old',
        payload: {
          'notes': [
            _record('n1', revision: 1, tags: ['private-sync-excluded']),
          ],
        },
      );
      builder.addBundle(
        fileId: 'new',
        payload: {
          'notes': [_record('n1', revision: 2)],
        },
      );
      expect(builder.finish().excludedNoteIds, isEmpty);
      expect(builder.finish().retainedBundleIds, isEmpty);
    });

    test('retains a tombstone after an excluded live version', () {
      final builder = SyncExclusionRetentionBuilder(
        localExcludedNoteIds: const {},
        isExcluded: (note) => note.tags.contains('private-sync-excluded'),
      );
      builder.addBundle(
        fileId: 'live',
        payload: {
          'notes': [
            _record('n1', revision: 1, tags: ['private-sync-excluded']),
          ],
        },
      );
      builder.addBundle(
        fileId: 'deleted',
        payload: {
          'notes': [_record('n1', revision: 2, action: 'delete')],
        },
      );
      expect(builder.finish().excludedNoteIds, {'n1'});
      expect(builder.finish().noteBundleIds, {'n1': 'deleted'});
    });
  });
}

Map<String, dynamic> _record(
  String id, {
  required int revision,
  String action = 'upsert',
  List<String> tags = const [],
  String? updatedAt,
}) => {
  'action': action,
  'note': NoteEntry(
    id: id,
    vaultId: 'v',
    title: 'title',
    body: 'body',
    createdAt: DateTime.utc(2024),
    updatedAt: updatedAt == null ? null : DateTime.parse(updatedAt),
    revision: revision,
    tags: tags,
  ).toJson(),
};
