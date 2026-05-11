import 'dart:convert';

import 'package:crypto/crypto.dart';

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
    required this.bytesBase64,
    required this.contentHash,
    required this.sizeBytes,
  });

  final String id;
  final AttachmentType type;
  final String label;
  final String bytesBase64;
  final String contentHash;
  final int sizeBytes;

  Map<String, dynamic> toJson({required bool inlineBytes}) {
    return {
      'id': id,
      'type': type.name,
      'label': label,
      'contentHash': contentHash,
      'sizeBytes': sizeBytes,
      if (inlineBytes) 'bytesBase64': bytesBase64,
    };
  }
}

class PreparedSyncNote {
  const PreparedSyncNote({required this.note, required this.action});

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

  int get estimatedMetadataPayloadBytes {
    var total = 4096;
    total += utf8.encode(deviceId).length;
    total += utf8.encode(exportedAt.toIso8601String()).length;
    for (final entry in notes) {
      total += utf8.encode(jsonEncode(entry.note.toJson())).length;
      total += 64;
    }
    for (final attachment in attachments) {
      total += utf8
          .encode(jsonEncode(attachment.toJson(inlineBytes: false)))
          .length;
      total += 64;
    }
    return total;
  }

  int get estimatedPayloadBytes {
    var total = 4096;
    total += utf8.encode(deviceId).length;
    total += utf8.encode(exportedAt.toIso8601String()).length;
    for (final entry in notes) {
      total += utf8.encode(jsonEncode(entry.note.toJson())).length;
      total += 64;
    }
    for (final attachment in attachments) {
      total += utf8.encode(attachment.id).length;
      total += utf8.encode(attachment.label).length;
      total += utf8.encode(attachment.bytesBase64).length;
      total += 64;
    }
    return total;
  }
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
    final changes = await loadPendingChanges();
    return _summarize(changes);
  }

  Future<List<PendingNoteChangeRecord>> loadPendingChanges() {
    return _database.loadPendingChanges();
  }

  Future<PreparedSyncSnapshot> prepareSnapshot(
    List<NoteEntry> notes, {
    List<PendingNoteChangeRecord>? pendingChanges,
  }) async {
    final changes = pendingChanges ?? await loadPendingChanges();
    final summary = _summarize(changes);
    final pendingById = {for (final change in changes) change.noteId: change};
    final attachmentPayloads = <PreparedSyncAttachment>[];
    final preparedNotes = <PreparedSyncNote>[];

    for (final note in notes) {
      final change = pendingById[note.id];
      if (change == null) {
        continue;
      }

      final attachmentIdsByPath = <String, String>{};

      Future<NoteAttachment> prepareAttachment(
        NoteAttachment attachment,
        int index,
      ) async {
        final filePath = attachment.filePath;
        if (filePath == null || filePath.isEmpty) {
          return attachment.copyWith(filePath: null, previewBytesBase64: null);
        }
        if (attachmentIdsByPath[filePath] case final existingId?) {
          return attachment.copyWith(
            filePath: 'sync-attachment-object://$existingId',
          );
        }
        final bytes = await _attachmentStore.readAttachment(
          filePath,
          type: attachment.type,
        );
        if (bytes == null || bytes.isEmpty) {
          return attachment.copyWith(filePath: null, previewBytesBase64: null);
        }
        final attachmentHash = sha256.convert(bytes).toString();
        final attachmentId = attachmentHash;
        attachmentIdsByPath[filePath] = attachmentId;
        attachmentPayloads.add(
          PreparedSyncAttachment(
            id: attachmentId,
            type: attachment.type,
            label: attachment.label,
            bytesBase64: base64Encode(bytes),
            contentHash: attachmentHash,
            sizeBytes: bytes.length,
          ),
        );
        return attachment.copyWith(
          filePath: 'sync-attachment-object://$attachmentId',
        );
      }

      final sanitizedAttachments = <NoteAttachment>[];
      for (var i = 0; i < note.attachments.length; i++) {
        sanitizedAttachments.add(
          await prepareAttachment(note.attachments[i], i),
        );
      }
      final sanitizedBlocks = <NoteBlock>[];
      for (var i = 0; i < note.blocks.length; i++) {
        final block = note.blocks[i];
        final attachment = block.attachment;
        sanitizedBlocks.add(
          attachment == null
              ? block
              : block.copyWith(
                  attachment: await prepareAttachment(
                    attachment,
                    note.attachments.length + i,
                  ),
                ),
        );
      }

      preparedNotes.add(
        PreparedSyncNote(
          note: note.copyWith(
            attachments: sanitizedAttachments,
            blocks: sanitizedBlocks,
            syncState: NoteSyncState.synced,
          ),
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

  Future<int> estimateNotesPayloadBytes(List<NoteEntry> notes) async {
    var total = 4096;
    final countedPaths = <String>{};
    for (final note in notes) {
      total += utf8.encode(jsonEncode(note.toJson())).length + 64;
      Future<void> addAttachment(NoteAttachment attachment) async {
        final filePath = attachment.filePath;
        if (filePath == null ||
            filePath.isEmpty ||
            !countedPaths.add(filePath)) {
          return;
        }
        final bytes = await _attachmentStore.readAttachment(
          filePath,
          type: attachment.type,
        );
        if (bytes == null || bytes.isEmpty) {
          return;
        }
        total += base64Encode(bytes).length;
        total += utf8.encode(attachment.label).length + 64;
      }

      for (final attachment in note.attachments) {
        await addAttachment(attachment);
      }
      for (final block in note.blocks) {
        final attachment = block.attachment;
        if (attachment != null) {
          await addAttachment(attachment);
        }
      }
    }
    return total;
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
