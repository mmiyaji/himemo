import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/sync_v2_profile_keys.dart';
import 'package:himemo/features/sync/data/sync_v2_attachment_service.dart';
import 'package:himemo/features/sync/data/sync_v2_header_codec.dart';
import 'package:himemo/features/sync/data/sync_v2_history.dart';
import 'package:himemo/features/sync/data/sync_v2_inbox.dart';
import 'package:himemo/features/sync/data/sync_v2_note_repository.dart';
import 'package:himemo/features/sync/data/sync_v2_payload_codec.dart';

class _CountingHeaders extends SyncV2HeaderCodec {
  _CountingHeaders(super.encryption);
  int opens = 0;
  @override
  Future<SyncV2Change> open(
    String encryptedHeader, {
    required String generationId,
    required String recordId,
    required SecretKey syncKey,
  }) {
    opens++;
    return super.open(
      encryptedHeader,
      generationId: generationId,
      recordId: recordId,
      syncKey: syncKey,
    );
  }
}

void main() {
  final syncKey = SecretKey(List.filled(32, 17));
  late SyncV2UnlockedProfileKey access;
  setUpAll(() async {
    final keys = SyncV2ProfileKeys(EncryptionService());
    final record = await keys.wrap(
      generationId: 'g',
      profileId: 'normal_0123456789abcdef',
      keyId: 'k',
      profileKey: SecretKey(List.filled(32, 29)),
      passphrase: 'test password',
      adminKey: syncKey,
    );
    access = await keys.unlockForAdminSession(
      generationId: 'g',
      record: record,
      adminKey: syncKey,
    );
  });
  ({SyncV2Inbox inbox, SyncV2NoteRepository repo, _CountingHeaders headers})
  device() {
    final encryption = EncryptionService();
    final headers = _CountingHeaders(encryption);
    final inbox = SyncV2Inbox(NativeDatabase.memory(), headers);
    return (
      inbox: inbox,
      headers: headers,
      repo: SyncV2NoteRepository(
        inbox,
        headers,
        SyncV2PayloadCodec(encryption),
      ),
    );
  }

  test(
    'multi-chunk writes and reads decrypt history once per operation',
    () async {
      final d = device();
      addTearDown(d.inbox.close);
      final service = SyncV2AttachmentService(d.inbox, d.repo);
      await service.store(
        generationId: 'g',
        syncKey: syncKey,
        profileAccess: access,
        bytes: Uint8List.fromList([1]),
        label: 'seed',
        type: 'file',
        stableId: 'seed',
      );
      d.headers.opens = 0;
      final bytes = Uint8List(2 * SyncV2AttachmentService.chunkBytes + 1);
      final ref = await service.store(
        generationId: 'g',
        syncKey: syncKey,
        profileAccess: access,
        bytes: bytes,
        label: 'three chunks',
        type: 'file',
        stableId: 'batch',
      );
      expect(ref.chunks.length, 3);
      expect(
        d.headers.opens,
        1,
        reason: 'One scan of the existing seed header',
      );
      d.headers.opens = 0;
      expect(
        await service.read(
          reference: ref,
          generationId: 'g',
          syncKey: syncKey,
          profileAccess: access,
        ),
        bytes,
      );
      expect(d.headers.opens, 4, reason: 'Each of four headers is opened once');
    },
  );

  test('chunks survive reversed interrupted delivery and reject corrupt references', () async {
    final a = device(), b = device();
    addTearDown(a.inbox.close);
    addTearDown(b.inbox.close);
    final service = SyncV2AttachmentService(a.inbox, a.repo);
    final target = SyncV2AttachmentService(b.inbox, b.repo);
    final bytes = Uint8List.fromList(
      List.generate(1024 * 1024 + 3, (i) => i % 251),
    );
    final ref = await service.store(
      generationId: 'g',
      syncKey: syncKey,
      profileAccess: access,
      bytes: bytes,
      label: 'photo',
      type: 'photo',
      stableId: 'stable',
    );
    await service.store(
      generationId: 'g',
      syncKey: syncKey,
      profileAccess: access,
      bytes: bytes,
      label: 'photo',
      type: 'photo',
      stableId: 'stable',
    );
    final queued = await a.inbox.readOutbox(generationId: 'g', limit: 100);
    expect(queued.length, 2);
    await b.inbox.stagePage(
      generationId: 'g',
      expectedCursor: null,
      nextCursor: '1',
      records: [
        for (final p in queued.reversed)
          (id: p.id, encryptedHeader: p.encryptedHeader),
      ],
      syncKey: syncKey,
    );
    await b.inbox.storePayload(
      generationId: 'g',
      recordId: queued.last.id,
      encryptedPayload: queued.last.encryptedPayload!,
      syncKey: syncKey,
    );
    await expectLater(
      target.read(
        reference: ref,
        generationId: 'g',
        syncKey: syncKey,
        profileAccess: access,
      ),
      throwsFormatException,
    );
    await b.inbox.storePayload(
      generationId: 'g',
      recordId: queued.first.id,
      encryptedPayload: queued.first.encryptedPayload!,
      syncKey: syncKey,
    );
    expect(
      await target.read(
        reference: ref,
        generationId: 'g',
        syncKey: syncKey,
        profileAccess: access,
      ),
      bytes,
    );
    final corrupt = SyncV2AttachmentReference.fromJson({
      ...ref.toJson(),
      'sha256': '0' * 64,
    });
    await expectLater(
      target.read(
        reference: corrupt,
        generationId: 'g',
        syncKey: syncKey,
        profileAccess: access,
      ),
      throwsFormatException,
    );
  });
}
