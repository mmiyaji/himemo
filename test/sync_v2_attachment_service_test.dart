import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/sync_v2_profile_keys.dart';
import 'package:himemo/features/sync/data/sync_v2_attachment_service.dart';
import 'package:himemo/features/sync/data/sync_v2_header_codec.dart';
import 'package:himemo/features/sync/data/sync_v2_inbox.dart';
import 'package:himemo/features/sync/data/sync_v2_note_repository.dart';
import 'package:himemo/features/sync/data/sync_v2_payload_codec.dart';

class _ReadTrackingRepository extends SyncV2NoteRepository {
  _ReadTrackingRepository(super.inbox, super.headers, super.payloadCodec);

  bool readComplete = false;

  @override
  Future<Map<String, SyncV2NoteSnapshot>> readMany({
    required String generationId,
    required String profileId,
    required SecretKey syncKey,
    required SyncV2UnlockedProfileKey profileKey,
    required Set<String> noteIds,
    void Function()? checkActive,
  }) async {
    readComplete = false;
    final result = await super.readMany(
      generationId: generationId,
      profileId: profileId,
      syncKey: syncKey,
      profileKey: profileKey,
      noteIds: noteIds,
      checkActive: checkActive,
    );
    readComplete = true;
    return result;
  }
}

void main() {
  test(
    'reads exact multi-chunk bytes and rejects tampered or missing data',
    () async {
      const generationId = 'generation_1';
      const profileId = 'profile_1';
      final encryption = EncryptionService();
      final headers = SyncV2HeaderCodec(encryption);
      final inbox = SyncV2Inbox(NativeDatabase.memory(), headers);
      final repository = _ReadTrackingRepository(
        inbox,
        headers,
        SyncV2PayloadCodec(encryption),
      );
      final syncKey = SecretKey(List<int>.filled(32, 17));
      final adminKey = SecretKey(List<int>.filled(32, 19));
      final keys = SyncV2ProfileKeys(encryption);
      final profileKey = SecretKey(List<int>.filled(32, 29));
      final wrapped = await keys.wrapAdminOnly(
        generationId: generationId,
        profileId: profileId,
        keyId: 'profile-key',
        profileKey: profileKey,
        adminKey: adminKey,
      );
      final access = await keys.unlockForAdminSession(
        generationId: generationId,
        record: wrapped,
        adminKey: adminKey,
      );
      addTearDown(() async {
        access.destroy();
        profileKey.destroy();
        adminKey.destroy();
        syncKey.destroy();
        await inbox.close();
      });

      final service = SyncV2AttachmentService(inbox, repository);
      final original = Uint8List.fromList(
        List<int>.generate(
          SyncV2AttachmentService.chunkBytes + 17,
          (index) => index % 251,
        ),
      );
      final reference = await service.store(
        generationId: generationId,
        syncKey: syncKey,
        profileAccess: access,
        bytes: original,
        label: 'two chunks',
        type: 'file',
        stableId: 'attachment-1',
      );
      expect(reference.chunks, hasLength(2));

      final restored = await service.read(
        reference: reference,
        generationId: generationId,
        syncKey: syncKey,
        profileAccess: access,
      );
      expect(restored, original);

      final corruptDigest = SyncV2AttachmentReference(
        id: reference.id,
        label: reference.label,
        type: reference.type,
        size: reference.size,
        sha256: '0' * 64,
        chunks: reference.chunks,
      );
      await expectLater(
        service.read(
          reference: corruptDigest,
          generationId: generationId,
          syncKey: syncKey,
          profileAccess: access,
        ),
        throwsFormatException,
      );

      final missingChunk = SyncV2AttachmentReference(
        id: reference.id,
        label: reference.label,
        type: reference.type,
        size: reference.size,
        sha256: reference.sha256,
        chunks: ['blob_${'0' * 64}', reference.chunks.last],
      );
      await expectLater(
        service.read(
          reference: missingChunk,
          generationId: generationId,
          syncKey: syncKey,
          profileAccess: access,
        ),
        throwsFormatException,
      );

      var checksAfterRead = 0;
      await expectLater(
        service.read(
          reference: reference,
          generationId: generationId,
          syncKey: syncKey,
          profileAccess: access,
          checkActive: () {
            if (repository.readComplete && ++checksAfterRead == 2) {
              throw StateError('cancelled');
            }
          },
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        await service.read(
          reference: reference,
          generationId: generationId,
          syncKey: syncKey,
          profileAccess: access,
        ),
        original,
      );
    },
  );
}
