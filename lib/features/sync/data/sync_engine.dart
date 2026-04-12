import '../../home/domain/note_entry.dart';
import '../../security/data/device_identity_store.dart';
import '../../security/data/encrypted_attachment_store.dart';
import '../../security/data/encrypted_note_database.dart';

class SyncQueueSummary {
  const SyncQueueSummary({
    required this.totalChanges,
    required this.upserts,
    required this.deletes,
    this.lastQueuedAt,
  });

  final int totalChanges;
  final int upserts;
  final int deletes;
  final DateTime? lastQueuedAt;

  bool get hasPendingChanges => totalChanges > 0;
}

class PreparedSyncAttachment {
  const PreparedSyncAttachment({
    required this.id,
    required this.type,
    required this.label,
    required this.encryptedPayload,
  });

  final String id;
  final AttachmentType type;
  final String label;
  final String encryptedPayload;
}

class PreparedSyncNote {
  const PreparedSyncNote({
    required this.note,
    required this.action,
  });

  final NoteEntry note;
  final PendingNoteChangeAction action;
}

class PreparedSyncSnapshot {
  const PreparedSyncSnapshot({
    required this.deviceId,
    required this.exportedAt,
    required this.summary,
    required this.notes,
    required this.attachments,
  });

  final String deviceId;
  final DateTime exportedAt;
  final SyncQueueSummary summary;
  final List<PreparedSyncNote> notes;
  final List<PreparedSyncAttachment> attachments;
}

class SyncEngine {
  SyncEngine({
    required EncryptedNoteDatabase database,
    required EncryptedAttachmentStore attachmentStore,
    required DeviceIdentityStore deviceIdentityStore,
  }) : _database = database,
       _attachmentStore = attachmentStore,
       _deviceIdentityStore = deviceIdentityStore;

  final EncryptedNoteDatabase _database;
  final EncryptedAttachmentStore _attachmentStore;
  final DeviceIdentityStore _deviceIdentityStore;

  Future<SyncQueueSummary> summarizeQueue() async {
    final changes = await _database.loadPendingChanges();
    return _summarize(changes);
  }

  Future<PreparedSyncSnapshot> prepareSnapshot(List<NoteEntry> notes) async {
    final pendingChanges = await _database.loadPendingChanges();
    final summary = _summarize(pendingChanges);
    final pendingById = {
      for (final change in pendingChanges) change.noteId: change,
    };
    final attachmentPayloads = <PreparedSyncAttachment>[];
    final preparedNotes = <PreparedSyncNote>[];

    for (final note in notes) {
      final change = pendingById[note.id];
      if (change == null) {
        continue;
      }

      final sanitizedAttachments = <NoteAttachment>[];
      for (var i = 0; i < note.attachments.length; i++) {
        final attachment = note.attachments[i];
        final filePath = attachment.filePath;
        if (filePath == null || filePath.isEmpty) {
          sanitizedAttachments.add(
            attachment.copyWith(filePath: null, previewBytesBase64: null),
          );
          continue;
        }
        final encryptedPayload = await _attachmentStore.readStoredPayload(
          filePath,
        );
        if (encryptedPayload == null || encryptedPayload.isEmpty) {
          sanitizedAttachments.add(
            attachment.copyWith(filePath: null, previewBytesBase64: null),
          );
          continue;
        }
        final attachmentId = '${note.id}-$i';
        attachmentPayloads.add(
          PreparedSyncAttachment(
            id: attachmentId,
            type: attachment.type,
            label: attachment.label,
            encryptedPayload: encryptedPayload,
          ),
        );
        sanitizedAttachments.add(
          attachment.copyWith(
            filePath: 'sync-attachment://$attachmentId',
            previewBytesBase64: null,
          ),
        );
      }

      preparedNotes.add(
        PreparedSyncNote(
          note: note.copyWith(attachments: sanitizedAttachments),
          action: change.action,
        ),
      );
    }

    return PreparedSyncSnapshot(
      deviceId: await _deviceIdentityStore.obtain(),
      exportedAt: DateTime.now(),
      summary: summary,
      notes: preparedNotes,
      attachments: attachmentPayloads,
    );
  }

  SyncQueueSummary _summarize(List<PendingNoteChangeRecord> changes) {
    final upserts = changes
        .where((change) => change.action == PendingNoteChangeAction.upsert)
        .length;
    final deletes = changes
        .where((change) => change.action == PendingNoteChangeAction.delete)
        .length;
    DateTime? lastQueuedAt;
    for (final change in changes) {
      final queuedAt = change.queuedAt;
      if (lastQueuedAt == null || queuedAt.isAfter(lastQueuedAt)) {
        lastQueuedAt = queuedAt;
      }
    }
    return SyncQueueSummary(
      totalChanges: changes.length,
      upserts: upserts,
      deletes: deletes,
      lastQueuedAt: lastQueuedAt,
    );
  }
}
