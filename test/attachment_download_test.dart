import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:himemo/app/network_connection.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/home/presentation/home_providers.dart';
import 'package:himemo/features/security/data/encrypted_attachment_store.dart';
import 'package:himemo/features/security/data/encrypted_note_database.dart';
import 'package:himemo/features/security/data/encrypted_note_store.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/master_key_service.dart';
import 'package:himemo/features/security/data/profile_data_key_service.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:himemo/features/sync/data/google_drive_sync_transport.dart';
import 'package:himemo/features/sync/data/secure_sync_bundle_store.dart';
import 'package:himemo/features/sync/data/sync_attachment_refs.dart';
import 'package:himemo/features/sync/data/sync_bundle_state_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  test(
    'reuploads private bytes when the cloud copy disappears after first upload',
    () async {
      SharedPreferences.setMockInitialValues({});
      final transport = _MissingObjectTransport();
      final h = await _createHarness(
        transport,
        prefix: 'himemo-private-reupload-',
        seed: 143,
      );
      addTearDown(h.dispose);
      await h.container
          .read(privateMemoProfilesControllerProvider.notifier)
          .addProfile(name: 'Private', password: 'private-reupload');
      final profile = await h.container
          .read(privateProfileUnlockControllerProvider.notifier)
          .unlockWithPassword('private-reupload');
      final stored = await h.attachmentStore.storeAttachment(
        XFile.fromData(Uint8List.fromList([3, 1, 4, 1]), name: 'photo.png'),
        type: AttachmentType.photo,
      );
      await h.container
          .read(notesControllerProvider.notifier)
          .upsert(
            NoteEntry(
              id: 'private-reupload',
              vaultId: profile!.vaultId,
              title: 'Private photo',
              body: '',
              createdAt: DateTime.now(),
              attachments: [
                NoteAttachment(
                  type: AttachmentType.photo,
                  label: 'photo.png',
                  filePath: stored,
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
      expect(transport.uploadCalls, 1);
      await h.container
          .read(notesControllerProvider.notifier)
          .reloadFromStorage();
      final reloaded = h.container.read(notesControllerProvider).single;
      expect(reloaded.attachments.single.filePath, stored);
      expect(
        await h.attachmentStore.readAttachment(
          stored!,
          type: AttachmentType.photo,
        ),
        [3, 1, 4, 1],
      );
      transport.missing = true;
      await sync.reuploadAllCurrentNotes();
      final state = h.container.read(syncTransferControllerProvider);
      expect(state.stage, SyncTransferStage.success, reason: state.message);
      expect(transport.uploadCalls, 2);
      expect(transport.missing, isFalse);
    },
  );
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.ruhenheim.himemo/network'),
          (_) async => 'mobile',
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.ruhenheim.himemo/network'),
          null,
        );
  });

  test(
    'downloads one remote attachment and updates note and block paths',
    () async {
      for (final type in <AttachmentType>[
        AttachmentType.photo,
        AttachmentType.audio,
        AttachmentType.file,
      ]) {
        await _withNetwork('mobile', () async {
          SharedPreferences.setMockInitialValues({});
          final transport = InMemoryGoogleDriveSyncTransport(
            uploadDelay: Duration.zero,
          );
          final h = await _createHarness(
            transport,
            prefix: 'himemo-attachment-download-${type.name}-',
            seed: 101 + type.index,
          );
          final bytes = <int>[type.index + 1, 7, 8, 9, 10];
          final storedPath = await h.attachmentStore.storeAttachment(
            XFile.fromData(
              Uint8List.fromList(bytes),
              name: 'remote.${_extensionFor(type)}',
            ),
            type: type,
          );
          final attachment = NoteAttachment(
            type: type,
            label: 'remote.${_extensionFor(type)}',
            filePath: storedPath,
          );
          final original = NoteEntry(
            id: 'download-${type.name}',
            vaultId: 'everyday',
            title: 'Keep this title',
            body: 'Keep this body',
            createdAt: DateTime.utc(2026, 9, 21, 10),
            updatedAt: DateTime.utc(2026, 9, 21, 10, 2),
            revision: 7,
            syncState: NoteSyncState.pendingUpload,
            attachments: [attachment],
            blocks: [
              NoteBlock(type: _blockTypeFor(type), attachment: attachment),
            ],
          );
          final notes = h.container.read(notesControllerProvider.notifier);
          await notes.upsert(original);
          await h.container
              .read(syncTransferControllerProvider.notifier)
              .uploadCurrentBundle(force: true);
          await notes.resetLocalStorage();

          await h.container
              .read(syncTransferControllerProvider.notifier)
              .downloadLatestBundle();
          await h.container
              .read(syncTransferControllerProvider.notifier)
              .applyDownloadedBundle();
          final remoteNote = h.container.read(notesControllerProvider).single;
          final remoteReference = remoteNote.attachments.single.filePath;
          expect(isSyncAttachmentObjectRef(remoteReference), isTrue);
          expect(
            remoteNote.blocks.single.attachment!.filePath,
            remoteReference,
          );

          final downloaded = await h.container
              .read(syncTransferControllerProvider.notifier)
              .downloadAttachment(remoteNote.attachments.single);
          expect(isSyncAttachmentObjectRef(downloaded.filePath), isFalse);
          expect(
            await h.attachmentStore.readAttachment(
              downloaded.filePath!,
              type: type,
            ),
            bytes,
          );

          final restored = h.container.read(notesControllerProvider).single;
          expect(restored.title, original.title);
          expect(restored.body, original.body);
          expect(restored.revision, original.revision);
          expect(restored.syncState, NoteSyncState.synced);
          expect(restored.attachments.single.filePath, downloaded.filePath);
          expect(
            restored.blocks.single.attachment!.filePath,
            downloaded.filePath,
          );
          await notes.reloadFromStorage();
          final reread = h.container.read(notesControllerProvider).single;
          expect(reread.attachments.single.filePath, downloaded.filePath);
          expect(
            reread.blocks.single.attachment!.filePath,
            downloaded.filePath,
          );
          expect(
            await h.attachmentStore.readAttachment(
              reread.attachments.single.filePath!,
              type: type,
            ),
            bytes,
          );
          final staleAttachment = remoteNote.attachments.single;
          await notes.upsert(
            reread.copyWith(
              title: 'Saved from stale editor snapshot',
              attachments: [staleAttachment],
              blocks: [
                NoteBlock(
                  type: _blockTypeFor(type),
                  attachment: staleAttachment,
                ),
              ],
            ),
          );
          final afterStaleSave = h.container
              .read(notesControllerProvider)
              .single;
          expect(afterStaleSave.title, 'Saved from stale editor snapshot');
          expect(
            afterStaleSave.attachments.single.filePath,
            downloaded.filePath,
          );
          expect(
            afterStaleSave.blocks.single.attachment!.filePath,
            downloaded.filePath,
          );
          await h.dispose();
        });
      }
    },
  );

  test(
    'private encrypted attachment requires an unlocked profile and preserves the ref while locked',
    () async {
      SharedPreferences.setMockInitialValues({});
      final transport = InMemoryGoogleDriveSyncTransport(
        uploadDelay: Duration.zero,
      );
      final h = await _createHarness(
        transport,
        prefix: 'himemo-private-attachment-download-',
        seed: 131,
      );
      final profiles = h.container.read(
        privateMemoProfilesControllerProvider.notifier,
      );
      expect(
        await profiles.addProfile(
          name: 'Download profile',
          password: 'download-pass',
        ),
        isNull,
      );
      final profile = await h.container
          .read(privateProfileUnlockControllerProvider.notifier)
          .unlockWithPassword('download-pass');
      expect(profile, isNotNull);
      final vaultId = profile!.vaultId;
      final bytes = <int>[31, 41, 59, 26, 53, 58];
      final encryptedPayload = await h.attachmentStore.encryptAttachmentBytes(
        bytes: bytes,
        type: AttachmentType.file,
        vaultId: vaultId,
      );
      final localPath = await h.attachmentStore.storeEncryptedPayload(
        encodedPayload: encryptedPayload,
        type: AttachmentType.file,
        fileNameHint: 'private.bin',
        vaultId: vaultId,
      );
      final attachment = NoteAttachment(
        type: AttachmentType.file,
        label: 'private.bin',
        filePath: localPath,
      );
      final notes = h.container.read(notesControllerProvider.notifier);
      await notes.upsert(
        NoteEntry(
          id: 'private-download',
          vaultId: vaultId,
          title: 'Private attachment',
          body: 'Encrypted body',
          createdAt: DateTime.utc(2026, 9, 21, 11),
          attachments: [attachment],
          blocks: [NoteBlock(type: NoteBlockType.file, attachment: attachment)],
        ),
      );
      final sync = h.container.read(syncTransferControllerProvider.notifier);
      await sync.uploadCurrentBundle(force: true);
      h.container.read(profileDataKeyServiceProvider).lockProfile(vaultId);
      await notes.resetLocalStorage();

      await sync.downloadLatestBundle();
      await sync.applyDownloadedBundle();
      final unlocked = await h.container
          .read(privateProfileUnlockControllerProvider.notifier)
          .unlockWithPassword('download-pass');
      expect(unlocked, isNotNull);
      final lockedApplyNote = h.container.read(notesControllerProvider).single;
      final remoteReference = lockedApplyNote.attachments.single.filePath;
      expect(isSyncAttachmentObjectRef(remoteReference), isTrue);

      h.container.read(profileDataKeyServiceProvider).lockProfile(vaultId);
      await expectLater(
        sync.downloadAttachment(lockedApplyNote.attachments.single),
        throwsA(anything),
      );
      expect(
        h.container
            .read(notesControllerProvider)
            .single
            .attachments
            .single
            .filePath,
        remoteReference,
      );

      await h.container
          .read(privateProfileUnlockControllerProvider.notifier)
          .unlockWithPassword('download-pass');
      final retriedNote = h.container.read(notesControllerProvider).single;
      final downloaded = await sync.downloadAttachment(
        retriedNote.attachments.single,
      );
      expect(isSyncAttachmentObjectRef(downloaded.filePath), isFalse);
      expect(
        await h.attachmentStore.readAttachment(
          downloaded.filePath!,
          type: AttachmentType.file,
        ),
        bytes,
      );
      final contentHash = downloaded.syncAttachmentContentHash;
      expect(contentHash, isNotNull);
      expect(contentHash, syncAttachmentObjectContentHash(remoteReference));
      await h.dispose();
    },
  );

  test('missing remote attachment keeps the ref and can be retried', () async {
    SharedPreferences.setMockInitialValues({});
    final transport = _FlakyDownloadTransport();
    final h = await _createHarness(
      transport,
      prefix: 'himemo-missing-attachment-download-',
      seed: 151,
    );
    final storedPath = await h.attachmentStore.storeAttachment(
      XFile.fromData(Uint8List.fromList([4, 5, 6]), name: 'retry.dat'),
      type: AttachmentType.file,
    );
    final notes = h.container.read(notesControllerProvider.notifier);
    await notes.upsert(
      NoteEntry(
        id: 'retry-note',
        vaultId: 'everyday',
        title: 'Retry',
        body: '',
        createdAt: DateTime.utc(2026, 9, 21, 12),
        attachments: [
          NoteAttachment(
            type: AttachmentType.file,
            label: 'retry.dat',
            filePath: storedPath,
          ),
        ],
      ),
    );
    final sync = h.container.read(syncTransferControllerProvider.notifier);
    await sync.uploadCurrentBundle(force: true);
    await notes.resetLocalStorage();
    await sync.downloadLatestBundle();
    await sync.applyDownloadedBundle();
    final remoteNote = h.container.read(notesControllerProvider).single;
    final remoteReference = remoteNote.attachments.single.filePath;
    expect(isSyncAttachmentObjectRef(remoteReference), isTrue);

    transport.failNextDownload = true;
    await expectLater(
      sync.downloadAttachment(remoteNote.attachments.single),
      throwsA(anything),
    );
    expect(
      h.container
          .read(notesControllerProvider)
          .single
          .attachments
          .single
          .filePath,
      remoteReference,
    );
    final retried = await sync.downloadAttachment(
      h.container.read(notesControllerProvider).single.attachments.single,
    );
    expect(isSyncAttachmentObjectRef(retried.filePath), isFalse);
    expect(transport.downloadCalls, 2);
    await h.dispose();
  });

  test(
    'concurrent downloads of one object issue one request and keep each label',
    () async {
      SharedPreferences.setMockInitialValues({});
      final transport = _PausingDownloadTransport();
      final h = await _createHarness(
        transport,
        prefix: 'himemo-dedup-attachment-download-',
        seed: 161,
      );
      final localPath = await h.attachmentStore.storeAttachment(
        XFile.fromData(Uint8List.fromList([71, 72, 73]), name: 'same.bin'),
        type: AttachmentType.file,
      );
      final notes = h.container.read(notesControllerProvider.notifier);
      await notes.upsert(
        NoteEntry(
          id: 'dedup-one',
          vaultId: 'everyday',
          title: 'One',
          body: '',
          createdAt: DateTime.utc(2026, 9, 21, 12),
          attachments: [
            NoteAttachment(
              type: AttachmentType.file,
              label: 'first.bin',
              filePath: localPath,
            ),
          ],
        ),
      );
      await notes.upsert(
        NoteEntry(
          id: 'dedup-two',
          vaultId: 'everyday',
          title: 'Two',
          body: '',
          createdAt: DateTime.utc(2026, 9, 21, 11),
          attachments: [
            NoteAttachment(
              type: AttachmentType.file,
              label: 'second.bin',
              filePath: localPath,
            ),
          ],
        ),
      );
      final sync = h.container.read(syncTransferControllerProvider.notifier);
      await sync.uploadCurrentBundle(force: true);
      await notes.resetLocalStorage();
      await sync.downloadLatestBundle();
      await sync.applyDownloadedBundle();
      final current = h.container.read(notesControllerProvider);
      final first = current
          .singleWhere((n) => n.id == 'dedup-one')
          .attachments
          .single;
      final second = current
          .singleWhere((n) => n.id == 'dedup-two')
          .attachments
          .single;
      final firstFuture = sync.downloadAttachment(first);
      await transport.started.future;
      final secondFuture = sync.downloadAttachment(second);
      transport.release.complete();
      final results = await Future.wait([firstFuture, secondFuture]);
      expect(transport.downloadCalls, 1);
      expect(results[0].label, 'first.bin');
      expect(results[1].label, 'second.bin');
      expect(results[0].filePath, results[1].filePath);
      await h.dispose();
    },
  );

  test('deferred downloads preserve edits, new notes, and deletions', () async {
    SharedPreferences.setMockInitialValues({});
    final transport = _PausingDownloadTransport();
    final h = await _createHarness(
      transport,
      prefix: 'himemo-deferred-attachment-download-',
      seed: 171,
    );
    final storedPath = await h.attachmentStore.storeAttachment(
      XFile.fromData(Uint8List.fromList([11, 22, 33]), name: 'deferred.png'),
      type: AttachmentType.photo,
    );
    final notes = h.container.read(notesControllerProvider.notifier);
    await notes.upsert(
      NoteEntry(
        id: 'deferred-target',
        vaultId: 'everyday',
        title: 'Before download',
        body: 'Before body',
        createdAt: DateTime.utc(2026, 9, 21, 13),
        updatedAt: DateTime.utc(2026, 9, 21, 13, 2),
        revision: 4,
        syncState: NoteSyncState.pendingUpload,
        attachments: [
          NoteAttachment(
            type: AttachmentType.photo,
            label: 'deferred.png',
            filePath: storedPath,
          ),
        ],
      ),
    );
    await notes.upsert(
      NoteEntry(
        id: 'deferred-delete',
        vaultId: 'everyday',
        title: 'Delete during download',
        body: '',
        createdAt: DateTime.utc(2026, 9, 21, 12),
      ),
    );
    final sync = h.container.read(syncTransferControllerProvider.notifier);
    await sync.uploadCurrentBundle(force: true);
    await notes.resetLocalStorage();
    await sync.downloadLatestBundle();
    await sync.applyDownloadedBundle();

    final targetBefore = h.container
        .read(notesControllerProvider)
        .singleWhere((n) => n.id == 'deferred-target');
    final downloading = sync.downloadDeferredAttachments();
    await transport.started.future;
    await notes.upsert(
      targetBefore.copyWith(
        title: 'Edited during download',
        body: 'Edited body survives',
        revision: targetBefore.revision + 1,
        syncState: NoteSyncState.pendingUpload,
      ),
    );
    await notes.upsert(
      NoteEntry(
        id: 'created-during-download',
        vaultId: 'everyday',
        title: 'Created during download',
        body: 'Keep me',
        createdAt: DateTime.utc(2026, 9, 21, 14),
        syncState: NoteSyncState.pendingUpload,
      ),
    );
    await notes.delete('deferred-delete');
    transport.release.complete();
    await downloading;

    final current = h.container.read(notesControllerProvider);
    final edited = current.singleWhere((n) => n.id == 'deferred-target');
    expect(edited.title, 'Edited during download');
    expect(edited.body, 'Edited body survives');
    expect(edited.revision, targetBefore.revision + 1);
    expect(edited.syncState, NoteSyncState.pendingUpload);
    expect(current.any((n) => n.id == 'created-during-download'), isTrue);
    final deleted = current.singleWhere((n) => n.id == 'deferred-delete');
    expect(deleted.deletedAt, isNotNull);
    expect(deleted.syncState, NoteSyncState.pendingDelete);
    await h.dispose();
  });
}

String _extensionFor(AttachmentType type) => switch (type) {
  AttachmentType.photo => 'png',
  AttachmentType.video => 'mp4',
  AttachmentType.audio => 'm4a',
  AttachmentType.file => 'bin',
};

NoteBlockType _blockTypeFor(AttachmentType type) => switch (type) {
  AttachmentType.photo => NoteBlockType.photo,
  AttachmentType.video => NoteBlockType.video,
  AttachmentType.audio => NoteBlockType.audio,
  AttachmentType.file => NoteBlockType.file,
};

Future<void> _withNetwork(String kind, Future<void> Function() body) async {
  const channel = MethodChannel('org.ruhenheim.himemo/network');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (_) async => kind);
  try {
    await body();
  } finally {
    messenger.setMockMethodCallHandler(channel, null);
  }
}

Future<_AttachmentDownloadHarness> _createHarness(
  GoogleDriveSyncTransport transport, {
  required String prefix,
  required int seed,
}) async {
  final directory = await Directory.systemTemp.createTemp(prefix);
  final secureStore = MemorySecureKeyValueStore();
  final encryptionService = EncryptionService(random: Random(seed));
  final masterKeyService = MasterKeyService(
    secureStore: secureStore,
    keyFactory: encryptionService.generateKeyBytes,
  );
  final profileDataKeyService = ProfileDataKeyService(
    secureStore: secureStore,
    encryptionService: encryptionService,
    normalMasterKeyService: masterKeyService,
  );
  final database = EncryptedNoteDatabase(executor: NativeDatabase.memory());
  final noteStore = EncryptedNoteStore(
    encryptionService: encryptionService,
    masterKeyService: masterKeyService,
    profileDataKeyService: profileDataKeyService,
    database: database,
    directoryProvider: () async => directory,
    sharedPreferencesProvider: SharedPreferences.getInstance,
  );
  final attachmentStore = EncryptedAttachmentStore(
    encryptionService: encryptionService,
    masterKeyService: masterKeyService,
    profileDataKeyService: profileDataKeyService,
    directoryProvider: () async => directory,
    sharedPreferencesProvider: SharedPreferences.getInstance,
  );
  final container = ProviderContainer(
    overrides: [
      secureKeyValueStoreProvider.overrideWithValue(secureStore),
      encryptionServiceProvider.overrideWithValue(encryptionService),
      masterKeyServiceProvider.overrideWithValue(masterKeyService),
      profileDataKeyServiceProvider.overrideWithValue(profileDataKeyService),
      encryptedNoteDatabaseProvider.overrideWithValue(database),
      encryptedNoteStoreProvider.overrideWithValue(noteStore),
      encryptedAttachmentStoreProvider.overrideWithValue(attachmentStore),
      secureSyncBundleStoreProvider.overrideWith(
        (ref) => SecureSyncBundleStore(
          encryptionService: encryptionService,
          syncBundleKeyService: ref.watch(syncBundleKeyServiceProvider),
          legacyMasterKeyService: masterKeyService,
          directoryProvider: () async => directory,
          sharedPreferencesProvider: SharedPreferences.getInstance,
        ),
      ),
      syncBundleStateStoreProvider.overrideWithValue(
        SyncBundleStateStore(storageKey: 'sync.bundle_state.$prefix'),
      ),
      googleDriveSyncTransportProvider.overrideWithValue(transport),
      syncAuthGatewayProvider.overrideWithValue(
        FakeGoogleDriveSyncAuthGateway(fallback: DefaultSyncAuthGateway()),
      ),
      networkConnectionServiceProvider.overrideWithValue(
        const NetworkConnectionService(),
      ),
    ],
  );
  await container
      .read(syncProviderControllerProvider.notifier)
      .setProvider(SyncProvider.googleDrive);
  await container
      .read(syncAuthControllerProvider.notifier)
      .connect(SyncProvider.googleDrive);
  await container.read(notesControllerProvider.notifier).restoreCompleted;
  return _AttachmentDownloadHarness(
    container: container,
    directory: directory,
    database: database,
    attachmentStore: attachmentStore,
  );
}

class _AttachmentDownloadHarness {
  const _AttachmentDownloadHarness({
    required this.container,
    required this.directory,
    required this.database,
    required this.attachmentStore,
  });

  final ProviderContainer container;
  final Directory directory;
  final EncryptedNoteDatabase database;
  final EncryptedAttachmentStore attachmentStore;

  Future<void> dispose() async {
    container.dispose();
    await database.close();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

class _MissingObjectTransport extends InMemoryGoogleDriveSyncTransport {
  _MissingObjectTransport() : super(uploadDelay: Duration.zero);
  bool missing = false;
  int uploadCalls = 0;

  @override
  Future<Set<String>> listAttachmentObjectContentHashes() async =>
      missing ? <String>{} : super.listAttachmentObjectContentHashes();

  @override
  Future<String?> downloadAttachmentObject(String contentHash) async =>
      missing ? null : super.downloadAttachmentObject(contentHash);

  @override
  Future<void> uploadAttachmentObject({
    required String contentHash,
    required String encodedPayload,
    required String type,
    required String label,
    required int sizeBytes,
    bool skipExistingCheck = false,
  }) async {
    uploadCalls++;
    missing = false;
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

class _FlakyDownloadTransport extends InMemoryGoogleDriveSyncTransport {
  _FlakyDownloadTransport() : super(uploadDelay: Duration.zero);

  bool failNextDownload = false;
  int downloadCalls = 0;

  @override
  Future<String?> downloadAttachmentObject(String contentHash) async {
    downloadCalls++;
    if (failNextDownload) {
      failNextDownload = false;
      return null;
    }
    return super.downloadAttachmentObject(contentHash);
  }
}

class _PausingDownloadTransport extends InMemoryGoogleDriveSyncTransport {
  _PausingDownloadTransport() : super(uploadDelay: Duration.zero);

  final started = Completer<void>();
  final release = Completer<void>();
  int downloadCalls = 0;

  @override
  Future<String?> downloadAttachmentObject(String contentHash) async {
    downloadCalls++;
    if (!started.isCompleted) {
      started.complete();
      await release.future;
    }
    return super.downloadAttachmentObject(contentHash);
  }
}
