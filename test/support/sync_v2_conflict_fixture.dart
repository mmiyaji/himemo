import 'package:drift/native.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/sync/data/sync_v2_attachment_service.dart';
import 'package:himemo/features/sync/data/sync_v2_header_codec.dart';
import 'package:himemo/features/sync/data/sync_v2_inbox.dart';
import 'package:himemo/features/sync/data/sync_v2_note_repository.dart';
import 'package:himemo/features/sync/data/sync_v2_note_store.dart';
import 'package:himemo/features/sync/data/sync_v2_payload_codec.dart';
import 'package:himemo/features/sync/presentation/sync_v2_workspace.dart';

Future<({SyncV2NoteStore store, NoteEntry note})> createSyncV2TestConflict(
  SyncV2WorkspaceController workspace,
) async {
  await workspace.saveNote(title: 'Base version', body: 'base text');
  final base = workspace.notes.single;
  final session = workspace.noteStoreSession!;
  final profileId = workspace.selectedProfileId!;
  final access = session.profiles[profileId]!;
  final encryption = EncryptionService();
  final headers = SyncV2HeaderCodec(encryption);
  final peer = SyncV2Inbox(NativeDatabase.memory(), headers);
  try {
    final seed = await workspace.inbox.readOutbox(
      generationId: session.generationId,
      limit: 100,
    );
    await peer.stagePage(
      generationId: session.generationId,
      expectedCursor: null,
      nextCursor: 'base',
      records: [
        for (final r in seed) (id: r.id, encryptedHeader: r.encryptedHeader),
      ],
      syncKey: session.syncKey,
    );
    for (final r in seed) {
      if (r.encryptedPayload != null) {
        await peer.storePayload(
          generationId: session.generationId,
          recordId: r.id,
          encryptedPayload: r.encryptedPayload!,
          syncKey: session.syncKey,
        );
      }
    }
    await workspace.saveNote(
      original: base,
      title: 'Local version',
      body: 'local text',
      blocks: [
        const NoteBlock(type: NoteBlockType.paragraph, text: 'local text'),
      ],
    );
    final repository = SyncV2NoteRepository(
      peer,
      headers,
      SyncV2PayloadCodec(encryption),
    );
    await repository.save(
      generationId: session.generationId,
      profileId: profileId,
      noteId: base.note.id,
      changeId: 'peer_change',
      expectedHeadIds: base.headIds,
      body: {
        'type': 'note',
        'note': base.note
            .copyWith(
              title: 'Remote version',
              body: 'remote text',
              blocks: [
                const NoteBlock(
                  type: NoteBlockType.paragraph,
                  text: 'remote text',
                ),
              ],
            )
            .toJson(),
        'attachments': [],
      },
      syncKey: session.syncKey,
      profileKey: access,
    );
    final changes = await peer.readOutbox(
      generationId: session.generationId,
      limit: 100,
    );
    await workspace.inbox.stagePage(
      generationId: session.generationId,
      expectedCursor: await workspace.inbox.readCursor(session.generationId),
      nextCursor: 'peer',
      records: [
        for (final r in changes) (id: r.id, encryptedHeader: r.encryptedHeader),
      ],
      syncKey: session.syncKey,
    );
    for (final r in changes) {
      await workspace.inbox.storePayload(
        generationId: session.generationId,
        recordId: r.id,
        encryptedPayload: r.encryptedPayload!,
        syncKey: session.syncKey,
      );
    }
  } finally {
    await peer.close();
  }
  await workspace.selectProfile(profileId);
  final store = SyncV2NoteStore(
    repository: workspace.repository,
    session: () => workspace.noteStoreSession,
    attachmentService: SyncV2AttachmentService(
      workspace.inbox,
      workspace.repository,
    ),
  );
  return (store: store, note: (await store.load(fallbackNotes: [])).single);
}
