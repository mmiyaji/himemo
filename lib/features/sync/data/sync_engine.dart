import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../home/domain/note_entry.dart';
import '../../security/data/device_identity_store.dart';
import '../../security/data/encrypted_attachment_store.dart';
import '../../security/data/encrypted_note_database.dart';
import 'sync_attachment_refs.dart';

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

class SyncSnapshotPreparationProgress {
  const SyncSnapshotPreparationProgress({
    required this.detail,
    required this.completedItems,
    required this.totalItems,
  });

  final String detail;
  final int completedItems;
  final int totalItems;
}

typedef SyncSnapshotPreparationProgressCallback =
    Future<void> Function(SyncSnapshotPreparationProgress progress);

class SyncAttachmentMissingException implements Exception {
  const SyncAttachmentMissingException({
    required this.noteId,
    required this.attachmentLabel,
    required this.attachmentType,
    required this.filePath,
    required this.index,
  });

  final String noteId;
  final String attachmentLabel;
  final AttachmentType attachmentType;
  final String filePath;
  final int index;

  @override
  String toString() {
    return 'sync.error.local_attachment_missing '
        'noteId=$noteId '
        'attachmentLabel=$attachmentLabel '
        'attachmentType=${attachmentType.name} '
        'filePath=$filePath '
        'index=$index';
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
    SyncSnapshotPreparationProgressCallback? onProgress,
  }) async {
    final changes = pendingChanges ?? await loadPendingChanges();
    final notesById = {for (final note in notes) note.id: note};
    final noteIds = changes.map((change) => change.noteId).toSet();
    final totalAttachments = notes
        .where((note) => noteIds.contains(note.id))
        .fold<int>(0, (total, note) {
          var count = total;
          for (final attachment in note.attachments) {
            if (attachment.filePath != null &&
                attachment.filePath!.isNotEmpty) {
              count += 1;
            }
          }
          for (final block in note.blocks) {
            final attachment = block.attachment;
            if (attachment?.filePath != null &&
                attachment!.filePath!.isNotEmpty) {
              count += 1;
            }
          }
          return count;
        });
    var preparedAttachmentCount = 0;
    final preparedChanges = <PendingNoteChangeRecord>[];
    final attachmentPayloads = <PreparedSyncAttachment>[];
    final preparedNotes = <PreparedSyncNote>[];

    for (final change in changes) {
      final note = notesById[change.noteId];
      if (note == null) {
        if (change.action == PendingNoteChangeAction.delete) {
          preparedChanges.add(change);
          preparedNotes.add(
            PreparedSyncNote(
              note: _deletedTombstoneFor(change),
              action: PendingNoteChangeAction.delete,
            ),
          );
        }
        continue;
      }
      preparedChanges.add(change);

      final attachmentIdsByPath = <String, String>{};

      Future<NoteAttachment> prepareAttachment(
        NoteAttachment attachment,
        int index,
      ) async {
        final filePath = attachment.filePath;
        if (filePath == null || filePath.isEmpty) {
          return attachment.copyWith(filePath: null, previewBytesBase64: null);
        }
        if (isSyncAttachmentObjectRef(filePath)) {
          preparedAttachmentCount += 1;
          await onProgress?.call(
            SyncSnapshotPreparationProgress(
              detail: 'Prepared attachment',
              completedItems: preparedAttachmentCount,
              totalItems: totalAttachments,
            ),
          );
          return attachment;
        }
        final storedMetadata = await _attachmentStore.storedPayloadMetadata(
          filePath,
        );
        final cachedContentHash = attachment.syncAttachmentContentHash;
        if (cachedContentHash != null &&
            cachedContentHash.isNotEmpty &&
            storedMetadata != null &&
            attachment.localPayloadSizeBytes == storedMetadata.sizeBytes &&
            attachment.localPayloadModifiedAtMillis != null &&
            attachment.localPayloadModifiedAtMillis ==
                storedMetadata.modifiedAtMillis) {
          preparedAttachmentCount += 1;
          await onProgress?.call(
            SyncSnapshotPreparationProgress(
              detail: 'Reused attachment',
              completedItems: preparedAttachmentCount,
              totalItems: totalAttachments,
            ),
          );
          return attachment.copyWith(
            filePath: syncAttachmentObjectRef(cachedContentHash),
          );
        }
        if (attachmentIdsByPath[filePath] case final existingId?) {
          preparedAttachmentCount += 1;
          await onProgress?.call(
            SyncSnapshotPreparationProgress(
              detail: 'Prepared attachment',
              completedItems: preparedAttachmentCount,
              totalItems: totalAttachments,
            ),
          );
          return attachment.copyWith(
            filePath: syncAttachmentObjectRef(existingId),
            localPayloadSizeBytes: storedMetadata?.sizeBytes,
            localPayloadModifiedAtMillis: storedMetadata?.modifiedAtMillis,
            syncAttachmentContentHash: existingId,
          );
        }
        await onProgress?.call(
          SyncSnapshotPreparationProgress(
            detail: 'Preparing attachment',
            completedItems: preparedAttachmentCount,
            totalItems: totalAttachments,
          ),
        );
        final bytes = await _attachmentStore.readAttachment(
          filePath,
          type: attachment.type,
        );
        if (bytes == null || bytes.isEmpty) {
          if (change.action == PendingNoteChangeAction.delete) {
            preparedAttachmentCount += 1;
            await onProgress?.call(
              SyncSnapshotPreparationProgress(
                detail: 'Prepared attachment',
                completedItems: preparedAttachmentCount,
                totalItems: totalAttachments,
              ),
            );
            return attachment.copyWith(
              filePath: null,
              previewBytesBase64: null,
            );
          }
          throw SyncAttachmentMissingException(
            noteId: note.id,
            attachmentLabel: attachment.label,
            attachmentType: attachment.type,
            filePath: filePath,
            index: index,
          );
        }
        final encoded = await _encodeSyncAttachmentBytes(bytes);
        final attachmentId = encoded['contentHash']!;
        attachmentIdsByPath[filePath] = attachmentId;
        attachmentPayloads.add(
          PreparedSyncAttachment(
            id: attachmentId,
            type: attachment.type,
            label: attachment.label,
            bytesBase64: encoded['bytesBase64']!,
            contentHash: encoded['contentHash']!,
            sizeBytes: bytes.length,
          ),
        );
        preparedAttachmentCount += 1;
        await onProgress?.call(
          SyncSnapshotPreparationProgress(
            detail: 'Prepared attachment',
            completedItems: preparedAttachmentCount,
            totalItems: totalAttachments,
          ),
        );
        return attachment.copyWith(
          filePath: syncAttachmentObjectRef(attachmentId),
          localPayloadSizeBytes: storedMetadata?.sizeBytes,
          localPayloadModifiedAtMillis: storedMetadata?.modifiedAtMillis,
          syncAttachmentContentHash: attachmentId,
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
      summary: _summarize(preparedChanges),
      notes: preparedNotes,
      attachments: attachmentPayloads,
    );
  }

  NoteEntry _deletedTombstoneFor(PendingNoteChangeRecord change) {
    final deletedAt = change.deletedAt ?? change.queuedAt;
    return NoteEntry(
      id: change.noteId,
      vaultId: change.vaultId,
      title: '',
      body: '',
      createdAt: change.queuedAt,
      updatedAt: change.queuedAt,
      deletedAt: deletedAt,
      revision: change.revision,
      syncState: NoteSyncState.synced,
      contentHash: change.contentHash,
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
        final estimatedBytes = await _attachmentStore
            .estimateStoredAttachmentPayloadBytes(filePath);
        if (estimatedBytes == null || estimatedBytes <= 0) {
          return;
        }
        total += _base64EncodedLength(estimatedBytes);
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

Future<Map<String, String>> _encodeSyncAttachmentBytes(List<int> bytes) {
  final transferable = TransferableTypedData.fromList([
    bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
  ]);
  return Isolate.run(() {
    final materialized = transferable.materialize().asUint8List();
    return {
      'contentHash': sha256.convert(materialized).toString(),
      'bytesBase64': base64Encode(materialized),
    };
  });
}

int _base64EncodedLength(int byteLength) => ((byteLength + 2) ~/ 3) * 4;
