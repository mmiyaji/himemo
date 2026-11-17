import '../../home/domain/note_entry.dart';
import '../../home/domain/note_tags.dart';
import '../../home/presentation/home_providers.dart' show VisibleTagSummary;
import 'sync_v2_workspace.dart';

/// Produces V1 sidebar summaries exclusively from the selected V2 profile.
List<VisibleTagSummary> syncV2TagSummaries(
  Iterable<SyncV2WorkspaceNote> notes,
  String? selectedProfileId,
) {
  if (selectedProfileId == null) return const [];
  final values = <String, VisibleTagSummary>{};
  for (final entry in notes) {
    final note = entry.note;
    if (note.vaultId != selectedProfileId ||
        !entry.ready ||
        entry.isConflict ||
        entry.isDeleted ||
        note.deletedAt != null ||
        note.archivedAt != null) {
      continue;
    }
    for (final tag in note.normalizedTags) {
      final key = canonicalizeNoteTag(tag);
      if (key.isEmpty) continue;
      final time = note.updatedAt ?? note.createdAt;
      final previous = values[key];
      values[key] = VisibleTagSummary(
        name: previous?.name ?? tag,
        count: (previous?.count ?? 0) + 1,
        latestAt: previous == null || time.isAfter(previous.latestAt)
            ? time
            : previous.latestAt,
      );
    }
  }
  final result = values.values.toList()
    ..sort((a, b) {
      final count = b.count.compareTo(a.count);
      if (count != 0) return count;
      final time = b.latestAt.compareTo(a.latestAt);
      return time != 0
          ? time
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  return List.unmodifiable(result);
}
