import 'dart:io';
import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/home/presentation/home_providers.dart';
import 'package:himemo/features/security/data/encrypted_attachment_store.dart';
import 'package:himemo/features/security/data/encrypted_note_database.dart';
import 'package:himemo/features/security/data/encrypted_note_store.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/master_key_service.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:himemo/features/sync/data/icloud_sync_transport.dart';
import 'package:himemo/features/sync/data/google_drive_sync_transport.dart';
import 'package:himemo/features/sync/data/remote_attachment_maintenance.dart';
import 'package:himemo/features/sync/data/secure_sync_bundle_store.dart';
import 'package:himemo/features/sync/data/sync_attachment_refs.dart';
import 'package:himemo/features/sync/data/sync_upload_reservations.dart';
import 'package:himemo/features/sync/data/sync_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('iCloud compaction collects only stale, unreferenced, unheld managed objects', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues({});
    final tempDirectory = await Directory.systemTemp.createTemp(
      'himemo-managed-gc-',
    );
    final secureStore = MemorySecureKeyValueStore();
    final encryptionService = EncryptionService(random: Random(84));
    final masterKeyService = MasterKeyService(
      secureStore: secureStore,
      keyFactory: encryptionService.generateKeyBytes,
    );
    final noteDatabase = EncryptedNoteDatabase(
      executor: NativeDatabase.memory(),
    );
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
    final transport = _AgeableInMemoryICloudSyncTransport();
    final container = ProviderContainer(
      overrides: [
        secureKeyValueStoreProvider.overrideWithValue(secureStore),
        iCloudSynchronizableKeyValueStoreProvider.overrideWithValue(
          secureStore,
        ),
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
            attachmentStore: ref.watch(encryptedAttachmentStoreProvider),
            directoryProvider: () async => tempDirectory,
            sharedPreferencesProvider: SharedPreferences.getInstance,
          ),
        ),
        iCloudSyncTransportProvider.overrideWithValue(transport),
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
        .setProvider(SyncProvider.iCloud);
    await container
        .read(syncAuthControllerProvider.notifier)
        .connect(SyncProvider.iCloud);
    await container.read(notesControllerProvider.notifier).restoreCompleted;

    Future<String> seedReleased(String hash, {bool age = false}) async {
      final id = await transport.pinAttachmentObject(
        contentHash: hash,
        uploadId: 'seed-$hash',
        encodedPayload: 'encrypted-payload-$hash',
        type: 'file',
        label: hash,
        sizeBytes: hash.length + 1,
      );
      await transport.releaseAttachmentObject(
        recordId: id,
        uploadId: 'seed-$hash',
        publishedBundleId: 'deleted-publication-for-$hash',
      );
      if (age) transport.ageIds.add(id);
      return id;
    }

    final collectibleId = await seedReleased('stale-unreferenced', age: true);
    final heldId = await transport.pinAttachmentObject(
      contentHash: 'held-pending-upload',
      uploadId: 'pending-upload-token',
      encodedPayload: 'encrypted-held-payload',
      type: 'file',
      label: 'pending',
      sizeBytes: 22,
    );
    final youngId = await seedReleased('young-unreferenced');
    final racingId = await seedReleased('pin-races-with-gc', age: true);
    transport.racePinId = racingId;
    final referencedHash = 'referenced-by-encrypted-note';
    final referencedId = await seedReleased(referencedHash);
    await transport.uploadAttachmentObject(
      contentHash: 'legacy-unmanaged',
      encodedPayload: 'legacy-encrypted-payload',
      type: 'file',
      label: 'legacy',
      sizeBytes: 24,
    );

    await container
        .read(notesControllerProvider.notifier)
        .upsert(
          NoteEntry(
            id: 'managed-gc-reference-note',
            vaultId: 'everyday',
            title: 'Attachment reference retained by a real full bundle',
            body: 'This note keeps its managed remote attachment alive.',
            createdAt: DateTime.utc(2026, 10, 1),
            attachments: [
              NoteAttachment(
                type: AttachmentType.file,
                label: 'reference.bin',
                filePath: syncAttachmentObjectRef(
                  referencedHash,
                  managed: true,
                ),
              ),
            ],
          ),
        );

    final result = await container
        .read(syncTransferControllerProvider.notifier)
        .compactICloudStorage();

    expect(result.deletedAttachmentCount, 1);
    expect(result.deletedAttachmentBytes, 'stale-unreferenced'.length + 1);
    final remaining = await transport.listManagedAttachmentObjects();
    final remainingIds = remaining.map((item) => item.id).toSet();
    expect(
      remainingIds,
      containsAll([heldId, youngId, racingId, referencedId]),
    );
    expect(remainingIds, isNot(contains(collectibleId)));
    expect(remaining.singleWhere((item) => item.id == heldId).uploadIds, {
      'pending-upload-token',
    });
    expect(
      remaining.singleWhere((item) => item.id == racingId).uploadIds,
      contains('gc-racing-pin'),
    );
    expect(
      await transport.downloadAttachmentObject('legacy-unmanaged'),
      'legacy-encrypted-payload',
    );
    expect(
      await transport.downloadAttachmentObject('stale-unreferenced'),
      isNull,
    );
    expect(await transport.downloadAttachmentObject(referencedHash), isNotNull);

    // A different device can recover a hold even after the original publishing
    // bundle was compacted and the originating device's journal was lost.
    final provenId = await transport.pinAttachmentObject(
      contentHash: 'receipt-protected-object',
      uploadId: 'lost-response-token',
      encodedPayload: 'receipt-object-payload',
      type: 'file',
      label: 'receipt',
      sizeBytes: 22,
    );
    final bundles = container.read(secureSyncBundleStoreProvider);
    final receipt = await bundles.writeBundle(
      PreparedSyncSnapshot(
        deviceId: 'other-device',
        exportedAt: DateTime.now().toUtc(),
        summary: const SyncQueueSummary(
          totalChanges: 0,
          upserts: 0,
          deletes: 0,
        ),
        notes: const [],
        attachments: const [],
      ),
      bundleKind: SyncBundleKind.delta,
      uploadReceipts: {'lost-response-token': 'already-compacted-publication'},
    );
    await transport.uploadBundle(
      encodedPayload: (await bundles.readEncryptedBundlePayload(
        receipt.reference,
      ))!,
      deviceId: 'other-device',
      noteCount: 0,
      attachmentCount: 0,
      bundleKind: SyncBundleKind.delta,
    );
    await container
        .read(syncTransferControllerProvider.notifier)
        .compactICloudStorage();
    final recovered = (await transport.listManagedAttachmentObjects())
        .singleWhere((item) => item.id == provenId);
    expect(recovered.uploadIds, isEmpty);
    expect(recovered.lastPublishedBundleId, 'already-compacted-publication');
    expect(
      (await transport.listManagedAttachmentObjects())
          .singleWhere((item) => item.id == heldId)
          .uploadIds,
      contains('pending-upload-token'),
    );
  });

  test('damaged local reservation hints cannot release server holds', () async {
    final store = MemorySecureKeyValueStore();
    for (final damaged in ['{broken', '{"token":42}', '[]']) {
      await store.write('damaged-journal', damaged);
      final journal = SyncUploadReservations('damaged-journal', store: store);
      expect(await journal.read(), isEmpty);
      await journal.start('new-upload');
      expect(await journal.read(), {'new-upload': null});
    }
  });

  test('upload reservation journal survives reconstruction until explicitly finished', () async {
    final store = MemorySecureKeyValueStore();
    final firstProcess = SyncUploadReservations(
      'managed-gc-journal',
      store: store,
    );
    await firstProcess.start('uncertain-upload');
    expect(
      await SyncUploadReservations('managed-gc-journal', store: store).read(),
      {'uncertain-upload': null},
    );
    await SyncUploadReservations(
      'managed-gc-journal',
      store: store,
    ).published('uncertain-upload', 'bundle-1');
    expect(await firstProcess.read(), {'uncertain-upload': 'bundle-1'});
    await SyncUploadReservations(
      'managed-gc-journal',
      store: store,
    ).finish('uncertain-upload');
    expect(await firstProcess.read(), isEmpty);
  });
}

class _AgeableInMemoryICloudSyncTransport extends InMemoryICloudSyncTransport {
  final Set<String> ageIds = {};
  String? racePinId;
  bool _raced = false;

  @override
  Future<List<ManagedAttachmentObject>> listManagedAttachmentObjects() async {
    final objects = await super.listManagedAttachmentObjects();
    final oldDate = DateTime.now().toUtc().subtract(const Duration(days: 8));
    return objects
        .map(
          (item) => ageIds.contains(item.id)
              ? ManagedAttachmentObject(
                  id: item.id,
                  contentHash: item.contentHash,
                  revision: item.revision,
                  modifiedAt: oldDate,
                  uploadIds: item.uploadIds,
                  lastPublishedBundleId: item.lastPublishedBundleId,
                  deleting: item.deleting,
                  sizeBytes: item.sizeBytes,
                )
              : item,
        )
        .toList(growable: false);
  }

  @override
  Future<bool> claimAndDeleteAttachmentObject(
    ManagedAttachmentObject candidate,
  ) async {
    if (!_raced && candidate.id == racePinId) {
      _raced = true;
      await super.pinAttachmentObject(
        contentHash: candidate.contentHash,
        uploadId: 'gc-racing-pin',
        type: 'file',
        label: 'racing writer',
        sizeBytes: candidate.sizeBytes,
      );
    }
    return super.claimAndDeleteAttachmentObject(candidate);
  }
}
