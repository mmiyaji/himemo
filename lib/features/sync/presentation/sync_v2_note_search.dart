import '../../home/domain/note_entry.dart';
import '../../home/domain/note_tags.dart';
import '../../home/presentation/home_providers.dart'
    show
        SearchFilters,
        SearchDateRange,
        SearchDateField,
        SearchAttachmentFilter;
import 'sync_v2_workspace.dart';

/// Filters only the currently selected V2 profile. No legacy note provider is read.
bool syncV2NoteMatchesFilters(
  SyncV2WorkspaceNote entry,
  SearchFilters filters, {
  required String? profileId,
  String query = '',
  DateTime? now,
}) {
  final note = entry.note;
  if (profileId == null ||
      note.vaultId != profileId ||
      entry.isDeleted ||
      note.deletedAt != null) {
    return false;
  }
  if (filters.archivedOnly
      ? note.archivedAt == null
      : (!filters.includeArchived && note.archivedAt != null)) {
    return false;
  }
  final needsContent =
      query.trim().isNotEmpty ||
      filters.pinnedOnly ||
      filters.withMediaOnly ||
      filters.attachmentFilters.isNotEmpty ||
      filters.tags.isNotEmpty ||
      filters.year != null ||
      filters.dateRange != SearchDateRange.all;
  if (needsContent && (!entry.ready || entry.isConflict)) return false;
  if (filters.year != null && note.createdAt.toLocal().year != filters.year) {
    return false;
  }
  final current = now ?? DateTime.now();
  final start = switch (filters.dateRange) {
    SearchDateRange.all => null,
    SearchDateRange.last7Days => current.subtract(const Duration(days: 7)),
    SearchDateRange.last30Days => current.subtract(const Duration(days: 30)),
    SearchDateRange.thisMonth => DateTime(current.year, current.month),
  };
  final date = filters.dateField == SearchDateField.updatedAt
      ? (note.updatedAt ?? note.createdAt)
      : note.createdAt;
  if (start != null && date.isBefore(start)) return false;
  if (filters.pinnedOnly && !note.isPinned) return false;
  final hasAttachment = note.attachments.isNotEmpty || note.location != null;
  if (filters.withMediaOnly && !hasAttachment) return false;
  if (filters.attachmentFilters.isNotEmpty &&
      !filters.attachmentFilters.any(
        (filter) => switch (filter) {
          SearchAttachmentFilter.all => true,
          SearchAttachmentFilter.any => hasAttachment,
          SearchAttachmentFilter.photo => note.attachments.any(
            (a) => a.type == AttachmentType.photo,
          ),
          SearchAttachmentFilter.video => note.attachments.any(
            (a) => a.type == AttachmentType.video,
          ),
          SearchAttachmentFilter.audio => note.attachments.any(
            (a) => a.type == AttachmentType.audio,
          ),
          SearchAttachmentFilter.location => note.location != null,
        },
      )) {
    return false;
  }
  final requiredTags = filters.tags
      .map(canonicalizeNoteTag)
      .where((tag) => tag.isNotEmpty)
      .toSet();
  if (requiredTags.isNotEmpty) {
    final tags = note.normalizedTags.map(canonicalizeNoteTag).toSet();
    if (!(filters.requireAllTags
        ? requiredTags.every(tags.contains)
        : requiredTags.any(tags.contains))) {
      return false;
    }
  }
  return query.trim().isEmpty || syncV2NoteMatchesSearch(entry, query);
}

/// Searches only a note whose current V2 payload is available and unambiguous.
/// Callers still own profile, deletion, archive, and visibility filtering.
bool syncV2NoteMatchesSearch(SyncV2WorkspaceNote entry, String query) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty ||
      !entry.ready ||
      entry.isConflict ||
      entry.isDeleted) {
    return false;
  }
  final note = entry.note;
  if (note.deletedAt != null) return false;

  if (note.title.toLowerCase().contains(normalizedQuery) ||
      note.body.toLowerCase().contains(normalizedQuery) ||
      note.tags.any((tag) => tag.toLowerCase().contains(normalizedQuery)) ||
      note.blocks.any(
        (block) => block.text?.toLowerCase().contains(normalizedQuery) ?? false,
      ) ||
      note.attachments.any(
        (attachment) =>
            attachment.label.toLowerCase().contains(normalizedQuery),
      ) ||
      (note.location?.address?.toLowerCase().contains(normalizedQuery) ??
          false) ||
      (note.location?.latitude.toString().contains(normalizedQuery) ?? false) ||
      (note.location?.longitude.toString().contains(normalizedQuery) ??
          false)) {
    return true;
  }

  return false;
}
