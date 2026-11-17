import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:himemo/app/app_flavor.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/home/presentation/home_providers.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:himemo/features/sync/data/sync_v2_enrollment_store.dart';
import 'package:himemo/features/sync/data/sync_v2_generation_registration.dart';
import 'package:himemo/features/sync/data/sync_v2_header_codec.dart';
import 'package:himemo/features/sync/data/sync_v2_inbox.dart';
import 'package:himemo/features/sync/data/sync_v2_note_repository.dart';
import 'package:himemo/features/sync/data/sync_v2_payload_codec.dart';
import 'package:himemo/features/sync/presentation/sync_v2_note_store_provider.dart';
import 'package:himemo/features/sync/presentation/sync_v2_workspace.dart';
import 'package:himemo/features/sync/testing/sync_v2_local_preview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'v2 providers commit canonical attachments and disable legacy sync',
    () async {
      SharedPreferences.setMockInitialValues({
        'settings.sync_provider': 'googleDrive',
      });
      configureFlavor(AppFlavor.development);
      final encryption = EncryptionService();
      final secure = MemorySecureKeyValueStore();
      final headers = SyncV2HeaderCodec(encryption);
      final inbox = SyncV2Inbox(NativeDatabase.memory(), headers);
      final registration = LocalPreviewRegistration(inbox);
      final enrollments = SyncV2EnrollmentStore(secure);
      final workspace = SyncV2WorkspaceController(
        inbox: inbox,
        repository: SyncV2NoteRepository(
          inbox,
          headers,
          SyncV2PayloadCodec(encryption),
        ),
        store: secure,
        enrollments: enrollments,
        registrationTransport: registration,
        registrationFactory: (_) =>
            SyncV2GenerationRegistration(registration, enrollments),
        syncOperation: () async => (
          headersStaged: false,
          hasMoreHeaders: false,
          downloadedPayloads: 0,
          publishedChanges: 0,
          errors: <String>[],
        ),
        activate: () async {},
        deactivate: () async {},
        supported: true,
        automaticSync: false,
      );
      addTearDown(workspace.dispose);
      await workspace.initialize();
      await workspace.prepareNew('1234');
      await workspace.confirmSetup();
      await workspace.createProfile('private', '5678');
      final privateId = workspace.selectedProfileId!;
      final container = ProviderContainer(
        overrides: [
          syncV2WorkspaceProvider.overrideWithValue(workspace),
          secureKeyValueStoreProvider.overrideWithValue(secure),
        ],
      );
      addTearDown(container.dispose);
      // Construct both default providers to exercise their lazy resolver cycle.
      final files = container.read(encryptedAttachmentStoreProvider);
      container.read(noteStoreProvider);
      expect(container.read(syncProviderControllerProvider), SyncProvider.off);
      await container
          .read(syncProviderControllerProvider.notifier)
          .setProvider(SyncProvider.googleDrive);
      expect(container.read(syncProviderControllerProvider), SyncProvider.off);
      final controller = container.read(notesControllerProvider.notifier);
      await controller.restoreCompleted;
      // XFile source is real; override the filesystem platform directory used by the adapter.
      // The dedicated store tests cover native draft files. Here v2 chunks are created by the workspace.
      await workspace.saveNote(
        title: 'photo',
        body: 'body',
        addedFiles: [
          SyncV2PendingAttachment(
            label: 'image.png',
            type: AttachmentType.photo,
            bytes: Uint8List.fromList([1, 2, 3]),
          ),
        ],
      );
      await controller.reloadFromStorage();
      final note = container
          .read(notesControllerProvider)
          .singleWhere((n) => n.title == 'photo');
      expect(note.vaultId, privateId);
      expect(note.attachments.single.filePath, startsWith('v2attachment:'));
      expect(
        await files.readAttachment(
          note.attachments.single.filePath!,
          type: AttachmentType.photo,
        ),
        [1, 2, 3],
      );
      await controller.upsert(note.copyWith(title: 'edited'));
      final edited = container
          .read(notesControllerProvider)
          .singleWhere((n) => n.title == 'edited');
      expect(edited.attachments, note.attachments);
      final drafts = container.read(noteEditorDraftStoreProvider);
      await drafts.save(
        NoteEditorDraftSnapshot(
          createdAt: DateTime.utc(2026),
          isPinned: false,
          editorMode: NoteEditorMode.quick,
          vaultId: privateId,
          tags: const [],
          quickContent: 'private draft',
          quickAttachments: edited.attachments,
          richBlocks: const [],
        ),
      );
      expect((await drafts.load())?.quickContent, 'private draft');
      workspace.lockPrivate();
      expect(await drafts.load(), isNull);
      await expectLater(
        files.readAttachment(
          edited.attachments.single.filePath!,
          type: AttachmentType.photo,
        ),
        throwsA(isA<Exception>()),
      );
    },
    skip: !usesSyncV2NoteBackend,
  );
}
