import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:cryptography/cryptography.dart';

import '../../home/domain/note_entry.dart';
import '../../security/data/sync_v2_profile_keys.dart';
import 'sync_v2_attachment_service.dart';
import 'sync_v2_inbox.dart';
import 'sync_v2_note_repository.dart';

typedef SyncV2CaptureFile = ({String label, String type, Uint8List bytes});

/// Widget/share captures always target authenticated normal-profile access.
/// A native acknowledgement retry never rereads deleted import files or
/// overwrites a capture that the user has since edited or deleted.
class SyncV2CaptureService {
  SyncV2CaptureService(this.inbox, this.repository);
  final SyncV2Inbox inbox;
  final SyncV2NoteRepository repository;

  Future<void> capture({
    required String generationId,
    required SecretKey syncKey,
    required SyncV2UnlockedProfileKey normalAccess,
    required String rawText,
    required String requestId,
    required Future<List<SyncV2CaptureFile>> Function() readFiles,
  }) async {
    if (!normalAccess.profileId.startsWith('normal_') ||
        normalAccess.generationId != generationId ||
        requestId.isEmpty ||
        requestId.length > 4096 ||
        utf8.encode(rawText).length > 2 * 1024 * 1024) {
      throw const FormatException('Invalid normal capture identity or content');
    }
    final identity = sha256
        .convert(utf8.encode(jsonEncode([generationId, requestId])))
        .toString();
    final noteId = 'note_capture_$identity';
    await inbox.transaction(() async {
      final existing = await repository.readNote(
        generationId: generationId,
        profileId: normalAccess.profileId,
        noteId: noteId,
        syncKey: syncKey,
        profileKey: normalAccess,
      );
      if (existing.headIds.isNotEmpty || existing.pendingIds.isNotEmpty) return;
      final files = await readFiles();
      if (rawText.trim().isEmpty && files.isEmpty) {
        throw const FormatException('Empty capture');
      }
      final references = <SyncV2AttachmentReference>[];
      for (var index = 0; index < files.length; index++) {
        final file = files[index];
        if (file.bytes.isEmpty ||
            file.bytes.length > SyncV2AttachmentService.maxBytes) {
          throw const FormatException('Attachment exceeds size limit');
        }
        AttachmentType.values.byName(file.type);
        references.add(
          await SyncV2AttachmentService(inbox, repository).store(
            generationId: generationId,
            syncKey: syncKey,
            profileAccess: normalAccess,
            bytes: file.bytes,
            label: file.label,
            type: file.type,
            stableId: 'capture:$identity:$index',
          ),
        );
      }
      final lines = const LineSplitter()
          .convert(rawText.trim())
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      final note = NoteEntry(
        id: noteId,
        vaultId: normalAccess.profileId,
        title: lines.isEmpty
            ? (files.length == 1 ? files.single.label : 'Shared attachments')
            : lines.first,
        body: lines.skip(1).join('\n'),
        createdAt: DateTime.now(),
        editorMode: NoteEditorMode.quick,
        attachments: [
          for (final ref in references)
            NoteAttachment(
              type: AttachmentType.values.byName(ref.type),
              label: ref.label,
              filePath: 'v2attachment:${ref.id}',
            ),
        ],
      );
      await repository.save(
        generationId: generationId,
        profileId: normalAccess.profileId,
        noteId: noteId,
        changeId: 'capture_$identity',
        expectedHeadIds: {},
        body: {
          'type': 'note',
          'note': note.toJson(),
          'attachments': [for (final ref in references) ref.toJson()],
        },
        syncKey: syncKey,
        profileKey: normalAccess,
      );
    });
  }
}
