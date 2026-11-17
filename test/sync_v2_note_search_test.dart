import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/home/presentation/home_providers.dart'
    show
        SearchFilters,
        SearchDateRange,
        SearchDateField,
        SearchAttachmentFilter;
import 'package:himemo/features/sync/data/sync_v2_history.dart';
import 'package:himemo/features/sync/data/sync_v2_note_repository.dart';
import 'package:himemo/features/sync/presentation/sync_v2_note_search.dart';
import 'package:himemo/features/sync/presentation/sync_v2_tag_summaries.dart';
import 'package:himemo/features/sync/presentation/sync_v2_workspace.dart';

SyncV2WorkspaceNote _entry({
  bool payloadAvailable = true,
  bool conflict = false,
}) {
  final note = NoteEntry(
    id: 'note-1',
    vaultId: 'profile-1',
    title: 'Meeting',
    body: 'Agenda',
    tags: const ['Work'],
    createdAt: DateTime(2026),
    blocks: const [NoteBlock(type: NoteBlockType.paragraph, text: 'decision')],
    attachments: const [
      NoteAttachment(type: AttachmentType.file, label: 'budget.pdf'),
    ],
  );
  SyncV2Change change(String id) => SyncV2Change(
    id: id,
    profileId: note.vaultId,
    noteId: note.id,
    operation: SyncV2Operation.upsert,
    parentIds: {},
    payloadDigest: 'digest-$id',
  );
  return SyncV2WorkspaceNote(
    note,
    SyncV2NoteSnapshot(
      versions: [
        SyncV2NoteVersion(
          change: change('change-1'),
          payloadAvailable: payloadAvailable,
          body: payloadAvailable
              ? {'type': 'note', 'note': note.toJson()}
              : null,
        ),
        if (conflict)
          SyncV2NoteVersion(
            change: SyncV2Change(
              id: 'change-2',
              profileId: note.vaultId,
              noteId: note.id,
              operation: SyncV2Operation.upsert,
              parentIds: {},
              payloadDigest: 'digest-2',
            ),
            payloadAvailable: false,
            body: null,
          ),
      ],
      pendingIds: {},
    ),
    const [],
  );
}

void main() {
  test('shared V1 sidebar summaries include only unlocked current-profile V2 notes', () {
    final valid = _entry();
    final private = SyncV2WorkspaceNote(
      valid.note.copyWith(vaultId: 'other', tags: ['Secret']),
      valid.snapshot,
      [],
    );
    final archived = SyncV2WorkspaceNote(
      valid.note.copyWith(archivedAt: DateTime.now(), tags: ['Archived']),
      valid.snapshot,
      [],
    );
    final unavailable = _entry(payloadAvailable: false);
    final partial = SyncV2WorkspaceNote(
      unavailable.note.copyWith(tags: ['Hidden']),
      unavailable.snapshot,
      [],
    );
    final conflict = _entry(conflict: true);
    final ambiguous = SyncV2WorkspaceNote(
      conflict.note.copyWith(tags: ['Conflict']),
      conflict.snapshot,
      [],
    );
    final result = syncV2TagSummaries([
      valid,
      private,
      archived,
      partial,
      ambiguous,
    ], 'profile-1');
    expect(result.map((e) => e.name), ['Work']);
    expect(result.single.count, 1);
    expect(syncV2TagSummaries([valid], null), isEmpty);
  });
  test(
    'searches tags, rich block text and attachment labels case insensitively',
    () {
      final entry = _entry();
      expect(syncV2NoteMatchesSearch(entry, 'WORK'), isTrue);
      expect(syncV2NoteMatchesSearch(entry, 'DECISION'), isTrue);
      expect(syncV2NoteMatchesSearch(entry, 'budget'), isTrue);
      expect(syncV2NoteMatchesSearch(entry, 'profile-1'), isFalse);
      expect(syncV2NoteMatchesSearch(entry, 'digest-change-1'), isFalse);
    },
  );

  test('does not search unavailable or conflicting V2 payloads', () {
    expect(
      syncV2NoteMatchesSearch(_entry(payloadAvailable: false), 'agenda'),
      isFalse,
    );
    expect(syncV2NoteMatchesSearch(_entry(conflict: true), 'agenda'), isFalse);
  });

  test('filters profile, tags, dates, attachment types and archive without reading unavailable content', () {
    final base = _entry();
    final note = base.note.copyWith(
      isPinned: true,
      tags: ['Work', 'Plan'],
      createdAt: DateTime(2026, 1, 2),
      updatedAt: DateTime(2026, 2, 25),
      attachments: [
        const NoteAttachment(type: AttachmentType.photo, label: 'photo.jpg'),
      ],
    );
    final entry = SyncV2WorkspaceNote(note, base.snapshot, []);
    final now = DateTime(2026, 3, 1);
    bool matches(SearchFilters f, {String? profile = 'profile-1'}) =>
        syncV2NoteMatchesFilters(entry, f, profileId: profile, now: now);
    expect(
      matches(
        const SearchFilters(
          pinnedOnly: true,
          tags: ['work', 'plan'],
          requireAllTags: true,
          dateRange: SearchDateRange.last7Days,
          dateField: SearchDateField.updatedAt,
          attachmentFilters: [SearchAttachmentFilter.photo],
        ),
      ),
      isTrue,
    );
    expect(
      matches(
        const SearchFilters(tags: ['work', 'missing'], requireAllTags: true),
      ),
      isFalse,
    );
    expect(matches(const SearchFilters(tags: ['work', 'missing'])), isTrue);
    expect(
      matches(const SearchFilters(dateRange: SearchDateRange.last7Days)),
      isFalse,
    );
    expect(
      matches(
        const SearchFilters(attachmentFilters: [SearchAttachmentFilter.audio]),
      ),
      isFalse,
    );
    expect(matches(const SearchFilters(year: 2025)), isFalse);
    expect(matches(const SearchFilters(), profile: 'other'), isFalse);
    final archived = SyncV2WorkspaceNote(
      note.copyWith(archivedAt: now),
      base.snapshot,
      [],
    );
    expect(
      syncV2NoteMatchesFilters(
        archived,
        const SearchFilters(),
        profileId: 'profile-1',
      ),
      isFalse,
    );
    expect(
      syncV2NoteMatchesFilters(
        archived,
        const SearchFilters(archivedOnly: true),
        profileId: 'profile-1',
      ),
      isTrue,
    );
    expect(
      syncV2NoteMatchesFilters(
        _entry(payloadAvailable: false),
        const SearchFilters(pinnedOnly: true),
        profileId: 'profile-1',
      ),
      isFalse,
    );
    expect(
      syncV2NoteMatchesFilters(
        _entry(conflict: true),
        const SearchFilters(tags: ['work']),
        profileId: 'profile-1',
      ),
      isFalse,
    );
  });
}
