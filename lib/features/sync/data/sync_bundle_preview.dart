import '../../home/domain/note_entry.dart';
import '../../security/data/encrypted_note_database.dart';

class SyncBundlePreview {
  const SyncBundlePreview({
    required this.deviceId,
    required this.exportedAt,
    required this.noteCount,
    required this.attachmentCount,
    required this.addedCount,
    required this.updatedCount,
    required this.removedCount,
    required this.privateVaultNoteCount,
    required this.sampleTitles,
    required this.addedTitles,
    required this.updatedTitles,
    required this.removedTitles,
  });

  final String? deviceId;
  final DateTime? exportedAt;
  final int noteCount;
  final int attachmentCount;
  final int addedCount;
  final int updatedCount;
  final int removedCount;
  final int privateVaultNoteCount;
  final List<String> sampleTitles;
  final List<String> addedTitles;
  final List<String> updatedTitles;
  final List<String> removedTitles;
}

SyncBundlePreview buildSyncBundlePreview({
  required Map<String, dynamic> decodedBundle,
  required List<NoteEntry> currentNotes,
}) {
  final importedChanges = [
    for (final rawEntry
        in (decodedBundle['notes'] as List<dynamic>? ?? const <dynamic>[]))
      _PreviewChange.fromRaw(Map<String, dynamic>.from(rawEntry as Map)),
  ];
  final importedNotes = importedChanges.map((change) => change.note).toList();
  final currentById = {for (final note in currentNotes) note.id: note};

  var addedCount = 0;
  var updatedCount = 0;
  var removedCount = 0;
  final addedTitles = <String>[];
  final updatedTitles = <String>[];
  final removedTitles = <String>[];
  for (final change in importedChanges) {
    final note = change.note;
    final current = currentById[note.id];
    if (change.action == PendingNoteChangeAction.delete) {
      removedCount += 1;
      removedTitles.add(_displayTitle(current ?? note));
      continue;
    }
    if (current == null) {
      addedCount += 1;
      addedTitles.add(_displayTitle(note));
      continue;
    }
    if (_isMeaningfullyDifferent(current, note)) {
      updatedCount += 1;
      updatedTitles.add(_displayTitle(note));
    }
  }

  final privateVaultNoteCount = importedNotes
      .where((note) => note.vaultId == 'private')
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
    privateVaultNoteCount: privateVaultNoteCount,
    sampleTitles: importedChanges
        .where((change) => change.action != PendingNoteChangeAction.delete)
        .map((change) => _displayTitle(change.note))
        .take(3)
        .toList(growable: false),
    addedTitles: addedTitles.take(5).toList(growable: false),
    updatedTitles: updatedTitles.take(5).toList(growable: false),
    removedTitles: removedTitles.take(5).toList(growable: false),
  );
}

class _PreviewChange {
  const _PreviewChange({required this.note, required this.action});

  final NoteEntry note;
  final PendingNoteChangeAction action;

  factory _PreviewChange.fromRaw(Map<String, dynamic> rawEntry) {
    final note = NoteEntry.fromJson(
      Map<String, dynamic>.from(rawEntry['note'] as Map),
    );
    final action = PendingNoteChangeAction.values.firstWhere(
      (value) => value.name == rawEntry['action'],
      orElse: () => note.deletedAt == null
          ? PendingNoteChangeAction.upsert
          : PendingNoteChangeAction.delete,
    );
    return _PreviewChange(note: note, action: action);
  }
}

String _displayTitle(NoteEntry note) {
  return note.title.trim().isEmpty ? '(Untitled)' : note.title;
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
