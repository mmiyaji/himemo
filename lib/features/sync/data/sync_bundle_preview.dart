import '../../home/domain/note_entry.dart';

class SyncBundlePreview {
  const SyncBundlePreview({
    required this.deviceId,
    required this.exportedAt,
    required this.noteCount,
    required this.attachmentCount,
    required this.addedCount,
    required this.updatedCount,
    required this.removedCount,
    required this.sampleTitles,
  });

  final String? deviceId;
  final DateTime? exportedAt;
  final int noteCount;
  final int attachmentCount;
  final int addedCount;
  final int updatedCount;
  final int removedCount;
  final List<String> sampleTitles;
}

SyncBundlePreview buildSyncBundlePreview({
  required Map<String, dynamic> decodedBundle,
  required List<NoteEntry> currentNotes,
}) {
  final importedNotes = <NoteEntry>[
    for (final rawEntry
        in (decodedBundle['notes'] as List<dynamic>? ?? const <dynamic>[]))
      NoteEntry.fromJson(
        Map<String, dynamic>.from(
          Map<String, dynamic>.from(rawEntry as Map)['note'] as Map,
        ),
      ),
  ];
  final importedIds = importedNotes.map((note) => note.id).toSet();
  final currentById = {
    for (final note in currentNotes) note.id: note,
  };

  var addedCount = 0;
  var updatedCount = 0;
  for (final note in importedNotes) {
    final current = currentById[note.id];
    if (current == null) {
      addedCount += 1;
      continue;
    }
    if (_isMeaningfullyDifferent(current, note)) {
      updatedCount += 1;
    }
  }

  final removedCount = currentNotes
      .where((note) => !importedIds.contains(note.id))
      .length;

  return SyncBundlePreview(
    deviceId: decodedBundle['deviceId'] as String?,
    exportedAt: decodedBundle['exportedAt'] == null
        ? null
        : DateTime.tryParse(decodedBundle['exportedAt'] as String),
    noteCount: importedNotes.length,
    attachmentCount:
        (decodedBundle['attachments'] as List<dynamic>? ?? const <dynamic>[])
            .length,
    addedCount: addedCount,
    updatedCount: updatedCount,
    removedCount: removedCount,
    sampleTitles: importedNotes
        .map((note) => note.title.trim().isEmpty ? '(Untitled)' : note.title)
        .take(3)
        .toList(growable: false),
  );
}

bool _isMeaningfullyDifferent(NoteEntry current, NoteEntry incoming) {
  if (current.revision != incoming.revision ||
      current.contentHash != incoming.contentHash ||
      current.deletedAt != incoming.deletedAt ||
      current.title != incoming.title ||
      current.body != incoming.body ||
      current.isPinned != incoming.isPinned ||
      current.attachments.length != incoming.attachments.length) {
    return true;
  }

  for (var i = 0; i < current.attachments.length; i++) {
    final left = current.attachments[i];
    final right = incoming.attachments[i];
    if (left.type != right.type ||
        left.label != right.label ||
        left.filePath != right.filePath) {
      return true;
    }
  }

  return false;
}
