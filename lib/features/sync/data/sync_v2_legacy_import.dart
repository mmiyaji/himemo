import 'dart:typed_data';

import '../../home/domain/note_entry.dart';

/// Validated contents of a decoded legacy ZIP, before assigning destinations.
class SyncV2LegacyImport {
  SyncV2LegacyImport._(
    this._notes,
    this.noteCountsByProfile,
    this.notesWithUnlinkedAttachments,
  );

  final List<NoteEntry> _notes;
  final Map<String, int> noteCountsByProfile;
  final int notesWithUnlinkedAttachments;

  factory SyncV2LegacyImport.inspect({
    required Map<String, Object?> manifest,
    required List<Map<String, dynamic>> notes,
    required Map<String, Uint8List> attachmentFiles,
  }) {
    if (manifest['format'] != 'org.ruhenheim.himemo.notes.zip' ||
        manifest['version'] != 1 ||
        manifest['noteCount'] != notes.length ||
        manifest['attachmentCount'] != attachmentFiles.length) {
      throw const FormatException('Invalid legacy HiMemo archive manifest');
    }
    final parsed = <NoteEntry>[];
    final counts = <String, int>{};
    final ids = <String>{};
    var unlinked = 0;
    for (final raw in notes) {
      final source = raw['vaultId'];
      if (source is! String ||
          (source != 'everyday' &&
              source != 'private' &&
              !_isCustomPrivate(source))) {
        throw const FormatException('Unknown legacy profile');
      }
      final note = NoteEntry.fromJson(raw);
      if (note.id.isEmpty || !ids.add(note.id)) {
        throw const FormatException('Duplicate or missing legacy note ID');
      }
      var hasUnlinked = false;
      for (final attachment in [
        ...note.attachments,
        for (final block in note.blocks) ?block.attachment,
      ]) {
        final path = attachment.filePath;
        if (path == null || path.isEmpty) {
          hasUnlinked = true;
          continue;
        }
        if (!path.startsWith('attachments/') ||
            path.contains(r'\') ||
            path.split('/').any((part) => part == '..' || part.isEmpty) ||
            attachmentFiles[path]?.isNotEmpty != true) {
          throw const FormatException('Invalid or missing legacy attachment');
        }
      }
      if (hasUnlinked) unlinked++;
      counts.update(source, (count) => count + 1, ifAbsent: () => 1);
      parsed.add(note);
    }
    return SyncV2LegacyImport._(
      List.unmodifiable(parsed),
      Map.unmodifiable(counts),
      unlinked,
    );
  }

  /// Returns notes only after every private destination has been confirmed.
  List<NoteEntry> mapDestinations({
    required Map<String, String> privateDestinations,
    required Set<String> unlockedPrivateProfiles,
    required bool acceptUnlinkedAttachments,
  }) {
    if (notesWithUnlinkedAttachments != 0 && !acceptUnlinkedAttachments) {
      throw StateError('Unlinked legacy attachments require confirmation');
    }
    final sourceProfiles = noteCountsByProfile.keys
        .where((id) => id != 'everyday')
        .toSet();
    final targets = privateDestinations.values.toSet();
    if (privateDestinations.length != sourceProfiles.length ||
        !sourceProfiles.containsAll(privateDestinations.keys) ||
        targets.length != sourceProfiles.length ||
        !targets.every(_isCustomPrivate) ||
        !unlockedPrivateProfiles.containsAll(targets)) {
      throw StateError('Invalid or locked legacy import destination');
    }
    return [
      for (final note in _notes)
        note.copyWith(
          vaultId: note.vaultId == 'everyday'
              ? 'everyday'
              : privateDestinations[note.vaultId]!,
        ),
    ];
  }
}

bool _isCustomPrivate(String id) =>
    id.startsWith('private_profile:') && id.length > 'private_profile:'.length;
