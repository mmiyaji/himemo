import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/home/presentation/home_providers.dart';
import 'package:himemo/features/security/data/encrypted_attachment_store.dart';
import 'package:himemo/features/security/data/encrypted_note_database.dart';
import 'package:himemo/features/security/data/encrypted_note_store.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/master_key_service.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:himemo/features/sync/data/secure_sync_bundle_store.dart';
import 'package:himemo/features/sync/data/google_drive_sync_transport.dart';
import 'package:himemo/features/sync/data/sync_bundle_state_store.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  test('review: reupload restores a missing remote object', () async {
    SharedPreferences.setMockInitialValues({});
    final transport = _ReviewTransport();
    final h = await _createGoogleDriveSyncHarness(
      transport,
      tempPrefix: 'himemo-review-reupload-',
    );
    final source = File('${h.tempDirectory.path}/source.png');
    await source.writeAsBytes([1, 2, 3, 4]);
    final localPath = await h.attachmentStore.storeAttachment(
      XFile(source.path),
      type: AttachmentType.photo,
    );
    await h.container
        .read(notesControllerProvider.notifier)
        .upsert(
          NoteEntry(
            id: 'review-note',
            vaultId: 'everyday',
            title: 'Photo',
            body: '',
            createdAt: DateTime.now(),
            attachments: [
              NoteAttachment(
                type: AttachmentType.photo,
                label: 'photo.png',
                filePath: localPath,
              ),
            ],
          ),
        );
    final sync = h.container.read(syncTransferControllerProvider.notifier);
    await sync.uploadCurrentBundle(force: true);
    expect(
      h.container.read(syncTransferControllerProvider).stage,
      SyncTransferStage.success,
    );
    expect(transport.objectUploads, 1);
    transport.remoteObjectMissing = true;
    await sync.reuploadAllCurrentNotes();
    expect(
      h.container.read(syncTransferControllerProvider).stage,
      SyncTransferStage.success,
    );
    expect(
      transport.objectUploads,
      2,
      reason:
          'The local photo still exists, but the remote object is missing. Reupload must restore it.',
    );
  });

  test(
    'review: removing one deduplicated attachment preserves the other note',
    () async {
      SharedPreferences.setMockInitialValues({});
      final transport = InMemoryGoogleDriveSyncTransport(
        uploadDelay: Duration.zero,
      );
      final h = await _createGoogleDriveSyncHarness(
        transport,
        tempPrefix: 'himemo-review-shared-',
      );
      final source = File('${h.tempDirectory.path}/source.png');
      await source.writeAsBytes([1, 2, 3, 4]);
      final localPath = await h.attachmentStore.storeAttachment(
        XFile(source.path),
        type: AttachmentType.photo,
      );
      final notes = h.container.read(notesControllerProvider.notifier);
      for (final id in ['first', 'second']) {
        await notes.upsert(
          NoteEntry(
            id: id,
            vaultId: 'everyday',
            title: id,
            body: '',
            createdAt: DateTime.now(),
            attachments: [
              NoteAttachment(
                type: AttachmentType.photo,
                label: 'photo.png',
                filePath: localPath,
              ),
            ],
          ),
        );
      }
      final sync = h.container.read(syncTransferControllerProvider.notifier);
      await sync.uploadCurrentBundle(force: true);
      // Import the uploaded bundle into an empty local database to exercise actual sync deduplication.
      await notes.resetLocalStorage();
      await sync.downloadLatestBundle();
      await sync.applyDownloadedBundle();
      expect(
        h.container.read(syncTransferControllerProvider).stage,
        SyncTransferStage.success,
      );
      final imported = h.container.read(notesControllerProvider);
      final first = imported.singleWhere((n) => n.id == 'first');
      final second = imported.singleWhere((n) => n.id == 'second');
      expect(
        first.attachments.single.filePath,
        second.attachments.single.filePath,
      );
      await notes.upsert(first.copyWith(attachments: []));
      final bytes = await h.attachmentStore.readAttachment(
        second.attachments.single.filePath!,
        type: AttachmentType.photo,
      );
      expect(
        bytes,
        [1, 2, 3, 4],
        reason:
            'Removing the image from the first memo must not delete the second memo image.',
      );
    },
  );
}

class _ReviewTransport extends InMemoryGoogleDriveSyncTransport {
  _ReviewTransport() : super(uploadDelay: Duration.zero);
  int objectUploads = 0;
  Completer<void>? downloadStarted;
  Completer<void>? releaseDownload;
  bool remoteObjectMissing = false;
  @override
  Future<Set<String>> listAttachmentObjectContentHashes() async =>
      remoteObjectMissing
      ? <String>{}
      : super.listAttachmentObjectContentHashes();
  @override
  Future<String?> downloadAttachmentObject(String hash) async {
    if (downloadStarted != null) {
      downloadStarted!.complete();
      await releaseDownload!.future;
      downloadStarted = null;
    }
    return remoteObjectMissing ? null : super.downloadAttachmentObject(hash);
  }

  @override
  Future<void> uploadAttachmentObject({
    required String contentHash,
    required String encodedPayload,
    required String type,
    required String label,
    required int sizeBytes,
    bool skipExistingCheck = false,
  }) async {
    objectUploads++;
    remoteObjectMissing = false;
    await super.uploadAttachmentObject(
      contentHash: contentHash,
      encodedPayload: encodedPayload,
      type: type,
      label: label,
      sizeBytes: sizeBytes,
      skipExistingCheck: skipExistingCheck,
    );
  }
}

Future<_GoogleDriveSyncHarness> _createGoogleDriveSyncHarness(
  GoogleDriveSyncTransport transport, {
  required String tempPrefix,
  int randomSeed = 66,
}) async {
  final tempDirectory = await Directory.systemTemp.createTemp(tempPrefix);
  final secureStore = MemorySecureKeyValueStore();
  final encryptionService = EncryptionService(random: Random(randomSeed));
  final masterKeyService = MasterKeyService(
    secureStore: secureStore,
    keyFactory: encryptionService.generateKeyBytes,
  );
  final noteDatabase = EncryptedNoteDatabase(executor: NativeDatabase.memory());
  final noteStore = EncryptedNoteStore(
    encryptionService: encryptionService,
    masterKeyService: masterKeyService,
    database: noteDatabase,
    directoryProvider: () async => tempDirectory,
    sharedPreferencesProvider: SharedPreferences.getInstance,
  );
  final attachmentStore = EncryptedAttachmentStore(
    encryptionService: encryptionService,
    masterKeyService: masterKeyService,
    directoryProvider: () async => tempDirectory,
    sharedPreferencesProvider: SharedPreferences.getInstance,
  );
  final container = ProviderContainer(
    overrides: [
      secureKeyValueStoreProvider.overrideWithValue(secureStore),
      encryptionServiceProvider.overrideWithValue(encryptionService),
      masterKeyServiceProvider.overrideWithValue(masterKeyService),
      encryptedNoteStoreProvider.overrideWithValue(noteStore),
      encryptedNoteDatabaseProvider.overrideWithValue(noteDatabase),
      encryptedAttachmentStoreProvider.overrideWithValue(attachmentStore),
      secureSyncBundleStoreProvider.overrideWith(
        (ref) => SecureSyncBundleStore(
          encryptionService: encryptionService,
          syncBundleKeyService: ref.watch(syncBundleKeyServiceProvider),
          legacyMasterKeyService: masterKeyService,
          directoryProvider: () async => tempDirectory,
          sharedPreferencesProvider: SharedPreferences.getInstance,
        ),
      ),
      syncBundleStateStoreProvider.overrideWithValue(
        SyncBundleStateStore(storageKey: 'sync.bundle_state.$tempPrefix'),
      ),
      googleDriveSyncTransportProvider.overrideWithValue(transport),
      syncAuthGatewayProvider.overrideWithValue(
        FakeGoogleDriveSyncAuthGateway(fallback: DefaultSyncAuthGateway()),
      ),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(noteDatabase.close);
  addTearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  await container
      .read(syncProviderControllerProvider.notifier)
      .setProvider(SyncProvider.googleDrive);
  await container
      .read(syncAuthControllerProvider.notifier)
      .connect(SyncProvider.googleDrive);
  await container.read(notesControllerProvider.notifier).restoreCompleted;

  return _GoogleDriveSyncHarness(
    container: container,
    tempDirectory: tempDirectory,
    attachmentStore: attachmentStore,
  );
}

class _GoogleDriveSyncHarness {
  const _GoogleDriveSyncHarness({
    required this.container,
    required this.tempDirectory,
    required this.attachmentStore,
  });

  final ProviderContainer container;
  final Directory tempDirectory;
  final EncryptedAttachmentStore attachmentStore;
}
