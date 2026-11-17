import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/sync/data/sync_v2_attachment_service.dart';
import 'package:himemo/features/sync/data/sync_v2_header_codec.dart';
import 'package:himemo/features/sync/data/sync_v2_inbox.dart';
import 'package:himemo/features/sync/data/sync_v2_note_repository.dart';
import 'package:himemo/features/sync/data/sync_v2_payload_codec.dart';
import 'package:himemo/features/sync/presentation/sync_v2_cloudkit_readonly.dart';

void main() {
  test('session close clears keys and prevents subsequent writes', () async {
    final store = SyncV2EphemeralKeyStore();
    await store.write('sync', 'secret');
    expect(await store.read('sync'), 'secret');
    store.clearSession();
    expect(await store.read('sync'), isNull);
    await expectLater(store.write('sync', 'late'), throwsStateError);
    expect(await store.read('sync'), isNull);
  });

  test('read-only transport rejects every publication', () async {
    const transport = SyncV2NeverWriteTransport();
    await expectLater(
      transport.publish(
        generationId: 'generation',
        publication: (
          id: 'record',
          encryptedHeader: 'header',
          encryptedPayload: null,
        ),
      ),
      throwsUnsupportedError,
    );
  });

  test('attachment reads reject conflicts and unlinked data', () async {
    final encryption = EncryptionService();
    final headers = SyncV2HeaderCodec(encryption);
    final inbox = SyncV2Inbox(NativeDatabase.memory(), headers);
    final controller = SyncV2CloudKitReadOnlyController(
      inbox: inbox,
      repository: SyncV2NoteRepository(
        inbox,
        headers,
        SyncV2PayloadCodec(encryption),
      ),
      encryption: encryption,
      store: SyncV2EphemeralKeyStore(),
      accountReader: () async => 'unused',
      registrationTransport: (_) => throw UnimplementedError(),
      readerFactory: (_) => throw UnimplementedError(),
    );
    addTearDown(controller.dispose);

    final hash = List.filled(64, 'a').join();
    final note = NoteEntry(
      id: 'note_test',
      vaultId: 'profile_test',
      title: 'sample',
      body: '',
      createdAt: DateTime.utc(2026),
    );
    final linked = NoteAttachment(
      type: AttachmentType.photo,
      label: 'image.png',
      filePath: 'v2attachment:$hash',
      syncAttachmentContentHash: hash,
    );
    final legacyLinked = linked.copyWith(syncAttachmentContentHash: null);
    final reference = SyncV2AttachmentReference(
      id: hash,
      label: 'image.png',
      type: 'photo',
      size: 1,
      sha256: hash,
      chunks: ['blob_$hash'],
    );
    final item = SyncV2ReadOnlyNote(
      note,
      conflicted: true,
      attachments: [reference],
    );
    expect(syncV2ReadOnlyAttachmentReference(item, linked), isNull);
    expect(syncV2ReadOnlyAttachmentReference(item, legacyLinked), isNull);
    await expectLater(
      controller.readAttachment(
        item: item,
        attachment: linked,
        isCurrent: () => true,
      ),
      throwsStateError,
    );

    final unlinked = SyncV2ReadOnlyNote(note, conflicted: false);
    expect(syncV2ReadOnlyAttachmentReference(unlinked, legacyLinked), isNull);
    await expectLater(
      controller.readAttachment(
        item: unlinked,
        attachment: linked,
        isCurrent: () => true,
      ),
      throwsStateError,
    );

    final nonConflicted = SyncV2ReadOnlyNote(
      note,
      conflicted: false,
      attachments: [reference],
    );
    expect(
      syncV2ReadOnlyAttachmentReference(nonConflicted, linked),
      same(reference),
    );
    expect(
      syncV2ReadOnlyAttachmentReference(nonConflicted, legacyLinked),
      same(reference),
    );
    expect(
      syncV2ReadOnlyAttachmentReference(
        nonConflicted,
        linked.copyWith(syncAttachmentContentHash: List.filled(64, 'b').join()),
      ),
      isNull,
    );
  });
}
