import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himemo/features/home/data/home_repository.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/home/domain/vault_models.dart';
import 'package:himemo/features/home/presentation/home_providers.dart';
import 'package:himemo/features/security/data/encrypted_attachment_store.dart';
import 'package:himemo/features/security/data/device_identity_store.dart';
import 'package:himemo/features/security/data/encrypted_note_database.dart';
import 'package:himemo/features/security/data/encrypted_note_store.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/master_key_service.dart';
import 'package:himemo/features/security/data/profile_data_key_service.dart';
import 'package:himemo/features/security/data/private_vault_secret_store.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:himemo/features/sync/data/google_drive_sync_transport.dart';
import 'package:himemo/features/sync/data/sync_conflict_policy.dart';
import 'package:himemo/features/sync/data/sync_bundle_preview.dart';
import 'package:himemo/features/sync/data/secure_sync_bundle_store.dart';
import 'package:himemo/features/sync/data/sync_bundle_key_service.dart';
import 'package:himemo/features/sync/data/sync_bundle_state_store.dart';
import 'package:himemo/features/sync/data/sync_engine.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('EncryptedNoteStore', () {
    late Directory tempDirectory;
    late MemorySecureKeyValueStore secureStore;
    late EncryptionService encryptionService;
    late SharedPreferences prefs;
    late EncryptedNoteDatabase database;
    late EncryptedNoteStore noteStore;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      tempDirectory = await Directory.systemTemp.createTemp(
        'himemo-secure-notes-',
      );
      secureStore = MemorySecureKeyValueStore();
      encryptionService = EncryptionService(random: Random(7));
      database = EncryptedNoteDatabase(executor: NativeDatabase.memory());
      noteStore = EncryptedNoteStore(
        encryptionService: encryptionService,
        masterKeyService: MasterKeyService(
          secureStore: secureStore,
          keyFactory: encryptionService.generateKeyBytes,
        ),
        database: database,
        directoryProvider: () async => tempDirectory,
        sharedPreferencesProvider: () async => prefs,
      );
    });

    tearDown(() async {
      await database.close();
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('migrates plaintext legacy notes into encrypted storage', () async {
      final notes = [
        NoteEntry(
          id: 'n1',
          vaultId: 'everyday',
          title: 'Encrypted title',
          body: 'Encrypted body',
          createdAt: DateTime(2026, 4, 12, 10, 0),
        ),
      ];
      await prefs.setString(
        'notes.entries.v1',
        jsonEncode([
          {
            'id': 'n1',
            'vaultId': 'everyday',
            'title': 'Encrypted title',
            'body': 'Encrypted body',
            'createdAt': '2026-04-12T10:00:00.000',
            'attachments': <Object>[],
            'isPinned': false,
          },
        ]),
      );

      final restored = await noteStore.load(fallbackNotes: const []);

      expect(restored, notes);
      expect(prefs.getString('notes.entries.v1'), isNull);
      final records = await database.loadAll();
      expect(records, hasLength(1));
      expect(
        records.single.note.encryptedPayload.contains('Encrypted body'),
        isFalse,
      );
    });

    test('persists and restores notes without plaintext leakage', () async {
      final notes = [
        NoteEntry(
          id: 'n9',
          vaultId: 'private',
          title: 'Vault plan',
          body: 'Only encrypted payload should be stored.',
          createdAt: DateTime(2026, 4, 12, 11, 30),
          updatedAt: DateTime(2026, 4, 12, 11, 45),
          deviceId: 'device-a',
          contentHash: 'hash-a',
          isPinned: true,
          revision: 4,
          syncState: NoteSyncState.pendingUpload,
          attachments: const [
            NoteAttachment(
              type: AttachmentType.photo,
              label: 'vault-proof.jpg',
              filePath: 'secure-attachment://vault-proof',
            ),
          ],
        ),
      ];

      await noteStore.save(notes);
      final restored = await noteStore.load(fallbackNotes: const []);

      expect(restored, notes);
      final records = await database.loadAll();
      expect(records, hasLength(1));
      final rawPayload = records.single.note.encryptedPayload;
      expect(rawPayload.contains('Vault plan'), isFalse);
      expect(
        rawPayload.contains('Only encrypted payload should be stored.'),
        isFalse,
      );
      expect(rawPayload.contains('vault-proof.jpg'), isFalse);
      expect(records.single.attachments, hasLength(1));
      expect(
        records.single.attachments.single.encryptedPayload.contains(
          'vault-proof.jpg',
        ),
        isFalse,
      );
      final pendingChanges = await database.loadPendingChanges();
      expect(pendingChanges, hasLength(1));
      expect(pendingChanges.single.noteId, 'n9');
      expect(pendingChanges.single.action, PendingNoteChangeAction.upsert);
    });

    test(
      'incrementally persists notes with long text and many attachments',
      () async {
        final body = List.generate(
          220,
          (index) => 'Long paragraph line ${index + 1} with plain memo text.',
        ).join('\n');
        final attachments = [
          for (var i = 0; i < 40; i++)
            NoteAttachment(
              type: i.isEven ? AttachmentType.photo : AttachmentType.file,
              label: 'attachment-$i.dat',
              filePath: 'secure-attachment://attachment-$i',
            ),
        ];
        final note = NoteEntry(
          id: 'large-note',
          vaultId: 'everyday',
          title: 'Large note',
          body: body,
          createdAt: DateTime(2026, 5, 6, 12, 0),
          updatedAt: DateTime(2026, 5, 6, 12, 5),
          attachments: attachments,
          blocks: [
            NoteBlock(type: NoteBlockType.paragraph, text: body),
            for (final attachment in attachments)
              NoteBlock(
                type: attachment.type == AttachmentType.photo
                    ? NoteBlockType.photo
                    : NoteBlockType.file,
                attachment: attachment,
              ),
          ],
          syncState: NoteSyncState.pendingUpload,
        );

        await noteStore.saveOne(note);
        final restored = await noteStore.load(fallbackNotes: const []);

        expect(restored.single, note);
        final records = await database.loadAll();
        expect(records.single.attachments, hasLength(40));
        expect(
          records.single.note.encryptedPayload.contains('Long paragraph'),
          isFalse,
        );
        expect(
          records.single.attachments.first.encryptedPayload.contains(
            'attachment-0',
          ),
          isFalse,
        );
      },
    );

    test(
      'migrates native encrypted blob into drift and removes legacy file',
      () async {
        final notes = [
          NoteEntry(
            id: 'n2',
            vaultId: 'everyday',
            title: 'Migrated note',
            body: 'This should move into sqlite.',
            createdAt: DateTime(2026, 4, 12, 12, 15),
            attachments: const [
              NoteAttachment(
                type: AttachmentType.audio,
                label: 'memo.m4a',
                filePath: 'secure-attachment://memo',
              ),
            ],
            syncState: NoteSyncState.pendingUpload,
          ),
        ];
        final key = await MasterKeyService(
          secureStore: secureStore,
          keyFactory: encryptionService.generateKeyBytes,
        ).obtainOrCreate();
        final encoded = await encryptionService.encryptJson(
          payload: {'notes': notes.map((note) => note.toJson()).toList()},
          secretKey: key,
        );
        final encryptedFile = File(
          '${tempDirectory.path}${Platform.pathSeparator}notes.entries.enc.v1',
        );
        await encryptedFile.writeAsString(encoded, flush: true);

        final restored = await noteStore.load(fallbackNotes: const []);

        expect(restored, notes);
        expect(await encryptedFile.exists(), isFalse);
        final records = await database.loadAll();
        expect(records, hasLength(1));
        expect(records.single.attachments, hasLength(1));
      },
    );

    test(
      'throws instead of falling back when encrypted notes are corrupt',
      () async {
        await database.replaceAll(
          notes: [
            EncryptedNoteRecord(
              id: 'corrupt-note',
              vaultId: 'everyday',
              encryptedPayload: 'not-json',
              createdAt: DateTime(2026, 4, 12, 12, 30),
              isPinned: false,
              revision: 1,
              syncState: NoteSyncState.localOnly,
            ),
          ],
          attachments: const [],
          pendingChanges: const [],
        );

        expect(
          () => noteStore.load(
            fallbackNotes: [
              NoteEntry(
                id: 'fallback',
                vaultId: 'everyday',
                title: 'Fallback',
                body: 'Should not be returned',
                createdAt: DateTime(2026, 4, 12, 13, 0),
              ),
            ],
          ),
          throwsA(isA<HimemoDecryptionException>()),
        );
      },
    );

    test('masks low-level decryption authentication failures', () async {
      final sourceKey = await MasterKeyService(
        secureStore: MemorySecureKeyValueStore(),
        keyFactory: encryptionService.generateKeyBytes,
      ).obtainOrCreate();
      final wrongKey = await MasterKeyService(
        secureStore: MemorySecureKeyValueStore(),
        keyFactory: encryptionService.generateKeyBytes,
      ).obtainOrCreate();
      final payload = await encryptionService.encryptJson(
        payload: const {'message': 'secret'},
        secretKey: sourceKey,
      );

      try {
        await encryptionService.decryptJson(
          encodedPayload: payload,
          secretKey: wrongKey,
        );
        fail('decryptJson should throw');
      } catch (error) {
        expect(error, isA<HimemoDecryptionException>());
        expect('$error', isNot(contains('SecretBoxAuthenticationError')));
        expect('$error', contains('復号できませんでした'));
      }
    });
  });

  group('PrivateVaultSecretStore', () {
    late MemorySecureKeyValueStore secureStore;
    late EncryptionService encryptionService;
    late SharedPreferences prefs;
    late PrivateVaultSecretStore secretStore;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      secureStore = MemorySecureKeyValueStore();
      encryptionService = EncryptionService(random: Random(9));
      secretStore = PrivateVaultSecretStore(
        secureStore: secureStore,
        encryptionService: encryptionService,
        sharedPreferencesProvider: () async => prefs,
      );
    });

    test('private profile notes require unlocked profile data key', () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'himemo-profile-key-notes-',
      );
      final database = EncryptedNoteDatabase(executor: NativeDatabase.memory());
      addTearDown(database.close);
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });
      final masterKeyService = MasterKeyService(
        secureStore: secureStore,
        keyFactory: encryptionService.generateKeyBytes,
      );
      final profileKeys = ProfileDataKeyService(
        secureStore: secureStore,
        encryptionService: encryptionService,
        normalMasterKeyService: masterKeyService,
      );
      await profileKeys.configureProfile(
        vaultId: 'private_profile:a',
        password: 'correct horse battery staple',
      );
      final profileStore = EncryptedNoteStore(
        encryptionService: encryptionService,
        masterKeyService: masterKeyService,
        profileDataKeyService: profileKeys,
        database: database,
        directoryProvider: () async => tempDirectory,
        sharedPreferencesProvider: () async => prefs,
      );
      final privateNote = NoteEntry(
        id: 'private-a',
        vaultId: 'private_profile:a',
        title: 'Secret profile title',
        body: 'Secret profile body',
        createdAt: DateTime(2026, 5, 6, 8, 0),
      );
      await profileStore.save([privateNote]);

      final lockedProfileKeys = ProfileDataKeyService(
        secureStore: secureStore,
        encryptionService: encryptionService,
        normalMasterKeyService: masterKeyService,
      );
      final lockedStore = EncryptedNoteStore(
        encryptionService: encryptionService,
        masterKeyService: masterKeyService,
        profileDataKeyService: lockedProfileKeys,
        database: database,
        directoryProvider: () async => tempDirectory,
        sharedPreferencesProvider: () async => prefs,
      );
      final locked = await lockedStore.load(fallbackNotes: const []);
      expect(locked.single.id, privateNote.id);
      expect(locked.single.title, 'Locked private note');
      expect(locked.single.body, isEmpty);

      expect(
        await lockedProfileKeys.unlockProfile(
          vaultId: 'private_profile:a',
          password: 'correct horse battery staple',
        ),
        isTrue,
      );
      final unlocked = await lockedStore.load(fallbackNotes: const []);
      expect(unlocked.single.title, privateNote.title);
      expect(unlocked.single.body, privateNote.body);
    });

    test(
      'stores and verifies private vault secret in secure storage',
      () async {
        expect(await secretStore.hasSecret(), isFalse);

        await secretStore.configure('top-secret');

        expect(await secretStore.hasSecret(), isTrue);
        expect(await secretStore.verify('top-secret'), isTrue);
        expect(await secretStore.verify('not-it'), isFalse);
        final stored = await secureStore.read(
          'security.private_vault.verifier.v1',
        );
        expect(stored, isNotNull);
        expect(stored!.contains('top-secret'), isFalse);
      },
    );

    test('migrates legacy verifier out of shared preferences', () async {
      final salt = encryptionService.generateSalt();
      final verifier = await encryptionService.deriveSecretVerifier(
        secret: 'legacy-secret',
        salt: salt,
      );
      await prefs.setString('security.private_vault_salt', base64Encode(salt));
      await prefs.setString('security.private_vault_digest', verifier);

      expect(await secretStore.hasSecret(), isTrue);
      expect(await secretStore.verify('legacy-secret'), isTrue);
      expect(prefs.getString('security.private_vault_salt'), isNull);
      expect(prefs.getString('security.private_vault_digest'), isNull);
    });
  });

  group('EncryptedAttachmentStore', () {
    late Directory tempDirectory;
    late MemorySecureKeyValueStore secureStore;
    late EncryptionService encryptionService;
    late SharedPreferences prefs;
    late MasterKeyService masterKeyService;
    late EncryptedAttachmentStore attachmentStore;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      tempDirectory = await Directory.systemTemp.createTemp(
        'himemo-secure-attachments-',
      );
      secureStore = MemorySecureKeyValueStore();
      encryptionService = EncryptionService(random: Random(13));
      masterKeyService = MasterKeyService(
        secureStore: secureStore,
        keyFactory: encryptionService.generateKeyBytes,
      );
      attachmentStore = EncryptedAttachmentStore(
        encryptionService: encryptionService,
        masterKeyService: masterKeyService,
        directoryProvider: () async => tempDirectory,
        sharedPreferencesProvider: () async => prefs,
      );
    });

    tearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('stores attachment bytes encrypted on disk', () async {
      final source = File(
        '${tempDirectory.path}${Platform.pathSeparator}raw.jpg',
      );
      await source.writeAsBytes(const [1, 2, 3, 4, 5, 6], flush: true);

      final storedReference = await attachmentStore.storeAttachment(
        XFile(source.path, name: 'raw.jpg'),
        type: AttachmentType.photo,
      );

      expect(storedReference, isNotNull);
      final encryptedFile = File(storedReference!);
      final rawContents = await encryptedFile.readAsString();
      expect(rawContents.contains('1, 2, 3'), isFalse);

      final restored = await attachmentStore.readAttachment(
        storedReference,
        type: AttachmentType.photo,
      );
      expect(restored, const [1, 2, 3, 4, 5, 6]);
    });

    test('reads attachments after app container path changes', () async {
      final source = File(
        '${tempDirectory.path}${Platform.pathSeparator}raw.jpg',
      );
      await source.writeAsBytes(const [7, 8, 9], flush: true);

      final storedReference = await attachmentStore.storeAttachment(
        XFile(source.path, name: 'raw.jpg'),
        type: AttachmentType.photo,
      );
      expect(storedReference, isNotNull);

      final staleContainerReference = path.join(
        tempDirectory.path,
        'previous-container',
        'attachments',
        path.basename(storedReference!),
      );
      final restored = await attachmentStore.readAttachment(
        staleContainerReference,
        type: AttachmentType.photo,
      );

      expect(restored, const [7, 8, 9]);
    });

    test(
      'reads private attachments when vault metadata uses stale path',
      () async {
        const vaultId = '$customPrivateVaultPrefix photos';
        final profileDataKeyService = ProfileDataKeyService(
          secureStore: secureStore,
          encryptionService: encryptionService,
          normalMasterKeyService: masterKeyService,
        );
        await profileDataKeyService.configureProfile(
          vaultId: vaultId,
          password: 'secret',
        );
        final privateAttachmentStore = EncryptedAttachmentStore(
          encryptionService: encryptionService,
          masterKeyService: masterKeyService,
          profileDataKeyService: profileDataKeyService,
          directoryProvider: () async => tempDirectory,
          sharedPreferencesProvider: () async => prefs,
        );
        final encrypted = await privateAttachmentStore.encryptAttachmentBytes(
          bytes: const [10, 11, 12],
          type: AttachmentType.photo,
          vaultId: vaultId,
        );
        final storedReference = await privateAttachmentStore
            .storeEncryptedPayload(
              encodedPayload: encrypted,
              type: AttachmentType.photo,
              fileNameHint: 'camera.jpg',
              vaultId: vaultId,
            );
        expect(storedReference, isNotNull);
        final staleReference = path.join(
          tempDirectory.path,
          'previous-container',
          'attachments',
          path.basename(storedReference!),
        );
        await prefs.remove('attachments.vault.$storedReference');
        await prefs.setString('attachments.vault.$staleReference', vaultId);

        final restored = await privateAttachmentStore.readAttachment(
          storedReference,
          type: AttachmentType.photo,
        );

        expect(restored, const [10, 11, 12]);
      },
    );

    test('recovers attachments that are mislabeled as private', () async {
      const vaultId = '$customPrivateVaultPrefix camera';
      final profileDataKeyService = ProfileDataKeyService(
        secureStore: secureStore,
        encryptionService: encryptionService,
        normalMasterKeyService: masterKeyService,
      );
      await profileDataKeyService.configureProfile(
        vaultId: vaultId,
        password: 'secret',
      );
      final privateAttachmentStore = EncryptedAttachmentStore(
        encryptionService: encryptionService,
        masterKeyService: masterKeyService,
        profileDataKeyService: profileDataKeyService,
        directoryProvider: () async => tempDirectory,
        sharedPreferencesProvider: () async => prefs,
      );
      final source = File(
        '${tempDirectory.path}${Platform.pathSeparator}camera.jpg',
      );
      await source.writeAsBytes(const [13, 14, 15], flush: true);
      final storedReference = await privateAttachmentStore.storeAttachment(
        XFile(source.path, name: 'camera.jpg'),
        type: AttachmentType.photo,
      );
      expect(storedReference, isNotNull);
      await prefs.setString('attachments.vault.$storedReference', vaultId);

      final restored = await privateAttachmentStore.readAttachment(
        storedReference!,
        type: AttachmentType.photo,
      );

      expect(restored, const [13, 14, 15]);
    });

    test('deletes unreferenced attachment payloads from storage', () async {
      final keptSource = File(
        '${tempDirectory.path}${Platform.pathSeparator}kept.jpg',
      );
      final orphanSource = File(
        '${tempDirectory.path}${Platform.pathSeparator}orphan.jpg',
      );
      await keptSource.writeAsBytes(const [1, 2, 3], flush: true);
      await orphanSource.writeAsBytes(const [4, 5, 6], flush: true);

      final keptReference = await attachmentStore.storeAttachment(
        XFile(keptSource.path, name: 'kept.jpg'),
        type: AttachmentType.photo,
      );
      final orphanReference = await attachmentStore.storeAttachment(
        XFile(orphanSource.path, name: 'orphan.jpg'),
        type: AttachmentType.photo,
      );

      final deletedCount = await attachmentStore.deleteUnreferencedAttachments({
        keptReference!,
      });

      expect(deletedCount, 1);
      expect(await File(keptReference).exists(), isTrue);
      expect(await File(orphanReference!).exists(), isFalse);
    });
  });

  test('NotesController deletes attachments removed during edit', () async {
    SharedPreferences.setMockInitialValues({});
    final tempDirectory = await Directory.systemTemp.createTemp(
      'himemo-notes-controller-',
    );
    final secureStore = MemorySecureKeyValueStore();
    final encryptionService = EncryptionService(random: Random(21));
    final fakeAttachmentStore = _TrackingEncryptedAttachmentStore(
      encryptionService: encryptionService,
      masterKeyService: MasterKeyService(
        secureStore: secureStore,
        keyFactory: encryptionService.generateKeyBytes,
      ),
      directoryProvider: () async => tempDirectory,
      sharedPreferencesProvider: SharedPreferences.getInstance,
    );
    final noteDatabase = EncryptedNoteDatabase(
      executor: NativeDatabase.memory(),
    );

    final container = ProviderContainer(
      overrides: [
        secureKeyValueStoreProvider.overrideWithValue(secureStore),
        encryptionServiceProvider.overrideWithValue(encryptionService),
        masterKeyServiceProvider.overrideWithValue(
          MasterKeyService(
            secureStore: secureStore,
            keyFactory: encryptionService.generateKeyBytes,
          ),
        ),
        encryptedNoteStoreProvider.overrideWithValue(
          EncryptedNoteStore(
            encryptionService: encryptionService,
            masterKeyService: MasterKeyService(
              secureStore: secureStore,
              keyFactory: encryptionService.generateKeyBytes,
            ),
            database: noteDatabase,
            directoryProvider: () async => tempDirectory,
            sharedPreferencesProvider: SharedPreferences.getInstance,
          ),
        ),
        encryptedNoteDatabaseProvider.overrideWithValue(noteDatabase),
        encryptedAttachmentStoreProvider.overrideWithValue(fakeAttachmentStore),
        deviceIdentityStoreProvider.overrideWithValue(
          DeviceIdentityStore(
            sharedPreferencesProvider: SharedPreferences.getInstance,
            random: Random(1),
          ),
        ),
        homeRepositoryProvider.overrideWithValue(_SingleNoteRepository()),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(noteDatabase.close);
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    final controller = container.read(notesControllerProvider.notifier);
    await controller.seedIfEmpty();
    final original = container.read(notesControllerProvider).single;
    await controller.upsert(
      original.copyWith(attachments: const <NoteAttachment>[]),
    );

    expect(fakeAttachmentStore.deletedReferences, ['secure-attachment://old']);
  });

  test(
    'NotesController cleanup removes orphaned attachment payloads',
    () async {
      SharedPreferences.setMockInitialValues({});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'himemo-storage-cleanup-',
      );
      final secureStore = MemorySecureKeyValueStore();
      final encryptionService = EncryptionService(random: Random(22));
      final masterKeyService = MasterKeyService(
        secureStore: secureStore,
        keyFactory: encryptionService.generateKeyBytes,
      );
      final attachmentStore = EncryptedAttachmentStore(
        encryptionService: encryptionService,
        masterKeyService: masterKeyService,
        directoryProvider: () async => tempDirectory,
        sharedPreferencesProvider: SharedPreferences.getInstance,
      );
      final noteDatabase = EncryptedNoteDatabase(
        executor: NativeDatabase.memory(),
      );

      final orphanSource = File(path.join(tempDirectory.path, 'orphan.jpg'));
      await orphanSource.writeAsBytes(List<int>.filled(128, 7), flush: true);
      final orphanReference = await attachmentStore.storeAttachment(
        XFile(orphanSource.path, name: 'orphan.jpg'),
        type: AttachmentType.photo,
      );

      final container = ProviderContainer(
        overrides: [
          secureKeyValueStoreProvider.overrideWithValue(secureStore),
          encryptionServiceProvider.overrideWithValue(encryptionService),
          masterKeyServiceProvider.overrideWithValue(masterKeyService),
          encryptedNoteStoreProvider.overrideWithValue(
            EncryptedNoteStore(
              encryptionService: encryptionService,
              masterKeyService: masterKeyService,
              database: noteDatabase,
              directoryProvider: () async => tempDirectory,
              sharedPreferencesProvider: SharedPreferences.getInstance,
            ),
          ),
          encryptedNoteDatabaseProvider.overrideWithValue(noteDatabase),
          encryptedAttachmentStoreProvider.overrideWithValue(attachmentStore),
          homeRepositoryProvider.overrideWithValue(_MinimalHomeRepository()),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(noteDatabase.close);
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });

      final controller = container.read(notesControllerProvider.notifier);
      final deletedCount = await controller.cleanupUnreferencedAttachments();
      final attachmentBytes = await attachmentStore.storagePayloadSizeBytes();

      expect(deletedCount, 1);
      expect(attachmentBytes, 0);
      expect(await File(orphanReference!).exists(), isFalse);
    },
  );

  test('NotesController writes sync metadata and tombstones deletes', () async {
    SharedPreferences.setMockInitialValues({});
    final tempDirectory = await Directory.systemTemp.createTemp(
      'himemo-sync-metadata-',
    );
    final secureStore = MemorySecureKeyValueStore();
    final encryptionService = EncryptionService(random: Random(31));
    final masterKeyService = MasterKeyService(
      secureStore: secureStore,
      keyFactory: encryptionService.generateKeyBytes,
    );
    final noteDatabase = EncryptedNoteDatabase(
      executor: NativeDatabase.memory(),
    );
    final container = ProviderContainer(
      overrides: [
        secureKeyValueStoreProvider.overrideWithValue(secureStore),
        encryptionServiceProvider.overrideWithValue(encryptionService),
        masterKeyServiceProvider.overrideWithValue(masterKeyService),
        encryptedNoteStoreProvider.overrideWithValue(
          EncryptedNoteStore(
            encryptionService: encryptionService,
            masterKeyService: masterKeyService,
            database: noteDatabase,
            directoryProvider: () async => tempDirectory,
            sharedPreferencesProvider: SharedPreferences.getInstance,
          ),
        ),
        encryptedNoteDatabaseProvider.overrideWithValue(noteDatabase),
        deviceIdentityStoreProvider.overrideWithValue(
          DeviceIdentityStore(
            sharedPreferencesProvider: SharedPreferences.getInstance,
            random: Random(5),
          ),
        ),
        homeRepositoryProvider.overrideWithValue(_MinimalHomeRepository()),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(noteDatabase.close);
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    final controller = container.read(notesControllerProvider.notifier);
    container.read(notesControllerProvider);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await controller.upsert(
      NoteEntry(
        id: 'sync-1',
        vaultId: 'everyday',
        title: 'Sync note',
        body: 'Pending upload',
        createdAt: DateTime(2026, 4, 12, 15, 0),
      ),
    );

    final saved = container
        .read(notesControllerProvider)
        .singleWhere((note) => note.id == 'sync-1');
    expect(saved.deviceId, isNotNull);
    expect(saved.contentHash, isNotNull);
    expect(saved.syncState, NoteSyncState.pendingUpload);
    expect(saved.deletedAt, isNull);

    await controller.delete('sync-1');
    final deleted = container
        .read(notesControllerProvider)
        .singleWhere((note) => note.id == 'sync-1');
    expect(deleted.deletedAt, isNotNull);
    expect(deleted.syncState, NoteSyncState.pendingDelete);
    expect(
      container.read(visibleNotesProvider).any((n) => n.id == 'sync-1'),
      isFalse,
    );
    final pendingChanges = await noteDatabase.loadPendingChanges();
    expect(pendingChanges, hasLength(1));
    expect(pendingChanges.single.noteId, 'sync-1');
    expect(pendingChanges.single.action, PendingNoteChangeAction.delete);
  });

  test(
    'NotesController can mark pending notes as synced and clear the queue',
    () async {
      SharedPreferences.setMockInitialValues({});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'himemo-mark-synced-',
      );
      final secureStore = MemorySecureKeyValueStore();
      final encryptionService = EncryptionService(random: Random(35));
      final masterKeyService = MasterKeyService(
        secureStore: secureStore,
        keyFactory: encryptionService.generateKeyBytes,
      );
      final noteDatabase = EncryptedNoteDatabase(
        executor: NativeDatabase.memory(),
      );
      final container = ProviderContainer(
        overrides: [
          secureKeyValueStoreProvider.overrideWithValue(secureStore),
          encryptionServiceProvider.overrideWithValue(encryptionService),
          masterKeyServiceProvider.overrideWithValue(masterKeyService),
          encryptedNoteStoreProvider.overrideWithValue(
            EncryptedNoteStore(
              encryptionService: encryptionService,
              masterKeyService: masterKeyService,
              database: noteDatabase,
              directoryProvider: () async => tempDirectory,
              sharedPreferencesProvider: SharedPreferences.getInstance,
            ),
          ),
          encryptedNoteDatabaseProvider.overrideWithValue(noteDatabase),
          deviceIdentityStoreProvider.overrideWithValue(
            DeviceIdentityStore(
              sharedPreferencesProvider: SharedPreferences.getInstance,
              random: Random(6),
            ),
          ),
          homeRepositoryProvider.overrideWithValue(_MinimalHomeRepository()),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(noteDatabase.close);
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });

      final controller = container.read(notesControllerProvider.notifier);
      container.read(notesControllerProvider);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await controller.upsert(
        NoteEntry(
          id: 'sync-2',
          vaultId: 'everyday',
          title: 'Uploaded note',
          body: 'Will become synced',
          createdAt: DateTime(2026, 4, 12, 15, 30),
        ),
      );

      expect(
        container
            .read(notesControllerProvider)
            .singleWhere((note) => note.id == 'sync-2')
            .syncState,
        NoteSyncState.pendingUpload,
      );
      expect(await noteDatabase.loadPendingChanges(), isNotEmpty);

      await controller.markCurrentStateSynced();

      expect(
        container
            .read(notesControllerProvider)
            .singleWhere((note) => note.id == 'sync-2')
            .syncState,
        NoteSyncState.synced,
      );
      expect(await noteDatabase.loadPendingChanges(), isEmpty);
    },
  );

  test(
    'SyncEngine prepares sanitized snapshot without local attachment paths',
    () async {
      SharedPreferences.setMockInitialValues({});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'himemo-sync-engine-',
      );
      final secureStore = MemorySecureKeyValueStore();
      final encryptionService = EncryptionService(random: Random(41));
      final masterKeyService = MasterKeyService(
        secureStore: secureStore,
        keyFactory: encryptionService.generateKeyBytes,
      );
      final attachmentStore = EncryptedAttachmentStore(
        encryptionService: encryptionService,
        masterKeyService: masterKeyService,
        directoryProvider: () async => tempDirectory,
        sharedPreferencesProvider: SharedPreferences.getInstance,
      );
      final database = EncryptedNoteDatabase(executor: NativeDatabase.memory());
      final noteStore = EncryptedNoteStore(
        encryptionService: encryptionService,
        masterKeyService: masterKeyService,
        database: database,
        directoryProvider: () async => tempDirectory,
        sharedPreferencesProvider: SharedPreferences.getInstance,
      );
      final source = File(
        '${tempDirectory.path}${Platform.pathSeparator}clip.jpg',
      );
      await source.writeAsBytes(const [9, 8, 7, 6], flush: true);
      final storedAttachment = await attachmentStore.storeAttachment(
        XFile(source.path, name: 'clip.jpg'),
        type: AttachmentType.photo,
      );
      final note = NoteEntry(
        id: 'sync-preview-1',
        vaultId: 'everyday',
        title: 'Snapshot',
        body: 'Pending queue item',
        createdAt: DateTime(2026, 4, 12, 16, 0),
        updatedAt: DateTime(2026, 4, 12, 16, 5),
        revision: 2,
        syncState: NoteSyncState.pendingUpload,
        deviceId: 'device-123',
        contentHash: 'hash-123',
        attachments: [
          NoteAttachment(
            type: AttachmentType.photo,
            label: 'clip.jpg',
            filePath: storedAttachment,
          ),
        ],
      );
      await noteStore.save([note]);
      final engine = SyncEngine(
        database: database,
        attachmentStore: attachmentStore,
        deviceIdentityStore: DeviceIdentityStore(
          sharedPreferencesProvider: SharedPreferences.getInstance,
          random: Random(42),
        ),
      );

      final summary = await engine.summarizeQueue();
      final snapshot = await engine.prepareSnapshot([note]);

      expect(summary.totalChanges, 1);
      expect(summary.upserts, 1);
      expect(snapshot.notes, hasLength(1));
      expect(snapshot.attachments, hasLength(1));
      expect(
        snapshot.notes.single.note.attachments.single.filePath,
        'sync-attachment://sync-preview-1-0',
      );
      expect(
        snapshot.notes.single.note.attachments.single.filePath,
        isNot(storedAttachment),
      );
      expect(
        snapshot.attachments.single.encryptedPayload.contains('clip.jpg'),
        isFalse,
      );

      await database.close();
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    },
  );

  test(
    'SecureSyncBundleStore writes encrypted bundle without plaintext note leakage',
    () async {
      SharedPreferences.setMockInitialValues({});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'himemo-sync-bundle-',
      );
      final secureStore = MemorySecureKeyValueStore();
      final encryptionService = EncryptionService(random: Random(51));
      final masterKeyService = MasterKeyService(
        secureStore: secureStore,
        keyFactory: encryptionService.generateKeyBytes,
      );
      final bundleStore = SecureSyncBundleStore(
        encryptionService: encryptionService,
        syncBundleKeyService: SyncBundleKeyService(
          secureStore: secureStore,
          keyFactory: encryptionService.generateKeyBytes,
        ),
        legacyMasterKeyService: masterKeyService,
        directoryProvider: () async => tempDirectory,
        sharedPreferencesProvider: SharedPreferences.getInstance,
      );
      final snapshot = PreparedSyncSnapshot(
        deviceId: 'device-export',
        exportedAt: DateTime(2026, 4, 12, 17, 0),
        summary: const SyncQueueSummary(
          totalChanges: 1,
          upserts: 1,
          deletes: 0,
        ),
        notes: [
          PreparedSyncNote(
            action: PendingNoteChangeAction.upsert,
            note: NoteEntry(
              id: 'export-1',
              vaultId: 'everyday',
              title: 'Sensitive title',
              body: 'Sensitive body',
              createdAt: DateTime(2026, 4, 12, 17, 0),
              attachments: const [
                NoteAttachment(
                  type: AttachmentType.photo,
                  label: 'secret.jpg',
                  filePath: 'sync-attachment://export-1-0',
                ),
              ],
            ),
          ),
        ],
        attachments: const [
          PreparedSyncAttachment(
            id: 'export-1-0',
            type: AttachmentType.photo,
            label: 'secret.jpg',
            encryptedPayload: '{"cipherText":"abc"}',
          ),
        ],
      );

      final stored = await bundleStore.writeBundle(
        snapshot,
        privateProfiles: const [
          {
            'version': 1,
            'profiles': [
              {
                'id': 'profile_sync',
                'name': 'Private',
                'createdAt': '2026-04-12T17:00:00.000',
              },
            ],
            'verifiers': [],
            'dataKeys': [],
          },
        ],
      );
      final file = File(stored.reference);
      final rawPayload = await file.readAsString();

      expect(rawPayload.contains('Sensitive title'), isFalse);
      expect(rawPayload.contains('Sensitive body'), isFalse);
      expect(rawPayload.contains('sync-attachment://export-1-0'), isFalse);

      final decoded = await bundleStore.readBundleJson(stored.reference);
      expect(decoded?['deviceId'], 'device-export');
      expect((decoded?['notes'] as List<dynamic>).length, 1);
      expect((decoded?['privateProfiles'] as List<dynamic>).length, 1);
      final encryptedPayload = await bundleStore.readEncryptedBundlePayload(
        stored.reference,
      );
      expect(encryptedPayload, isNotNull);
      expect(encryptedPayload!.contains('Sensitive title'), isFalse);
      final copied = await bundleStore.writeEncryptedBundlePayload(
        encryptedPayload,
        noteCount: stored.noteCount,
        attachmentCount: stored.attachmentCount,
        fileNameOverride: 'copied_bundle.enc',
      );
      final copiedDecoded = await bundleStore.readBundleJson(copied.reference);
      expect(copiedDecoded?['deviceId'], 'device-export');

      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    },
  );

  test(
    'ProfileDataKeyService exports and imports wrapped profile keys',
    () async {
      final encryptionService = EncryptionService(random: Random(71));
      final sourceStore = MemorySecureKeyValueStore();
      final targetStore = MemorySecureKeyValueStore();
      final sourceMasterKey = MasterKeyService(
        secureStore: sourceStore,
        keyFactory: encryptionService.generateKeyBytes,
      );
      final targetMasterKey = MasterKeyService(
        secureStore: targetStore,
        keyFactory: encryptionService.generateKeyBytes,
      );
      final source = ProfileDataKeyService(
        secureStore: sourceStore,
        encryptionService: encryptionService,
        normalMasterKeyService: sourceMasterKey,
      );
      final target = ProfileDataKeyService(
        secureStore: targetStore,
        encryptionService: encryptionService,
        normalMasterKeyService: targetMasterKey,
      );
      const vaultId = 'private_profile:sync-profile';

      await source.configureProfile(vaultId: vaultId, password: 'profile-pass');
      final exported = await source.exportWrappedProfileKeys([vaultId]);
      final imported = await target.importWrappedProfileKeys(exported);

      expect(imported, 1);
      expect(
        await target.unlockProfile(vaultId: vaultId, password: 'wrong'),
        isFalse,
      );
      expect(
        await target.unlockProfile(vaultId: vaultId, password: 'profile-pass'),
        isTrue,
      );
      expect(target.isProfileUnlocked(vaultId), isTrue);
    },
  );

  test(
    'SyncBundleKeyService creates stable fingerprint from secure storage',
    () async {
      final secureStore = MemorySecureKeyValueStore();
      final service = SyncBundleKeyService(
        secureStore: secureStore,
        keyFactory: () => List<int>.generate(32, (index) => index),
      );

      final first = await service.fingerprint();
      final second = await service.fingerprint();

      expect(first, hasLength(12));
      expect(second, first);
    },
  );

  test('SyncBundleKeyService can export and import backup codes', () async {
    final sourceStore = MemorySecureKeyValueStore();
    final sourceService = SyncBundleKeyService(
      secureStore: sourceStore,
      keyFactory: () => List<int>.generate(32, (index) => index + 1),
    );
    final backupCode = await sourceService.exportBackupCode();
    final expectedFingerprint = await sourceService.fingerprint();

    final targetStore = MemorySecureKeyValueStore();
    final targetService = SyncBundleKeyService(
      secureStore: targetStore,
      keyFactory: () => List<int>.generate(32, (index) => 99 - index),
    );
    final importedFingerprint = await targetService.importBackupCode(
      backupCode,
    );

    expect(importedFingerprint, expectedFingerprint);
    expect(await targetService.fingerprint(), expectedFingerprint);
  });

  test(
    'SyncBundleKeyService adopts cloud backup code before local key',
    () async {
      final localStore = MemorySecureKeyValueStore();
      final localService = SyncBundleKeyService(
        secureStore: localStore,
        keyFactory: () => List<int>.filled(32, 1),
      );
      await localService.obtainOrCreate();

      final cloudSource = SyncBundleKeyService(
        secureStore: MemorySecureKeyValueStore(),
        keyFactory: () => List<int>.filled(32, 2),
      );
      final cloudBackupCode = await cloudSource.exportBackupCode();
      final cloudFingerprint = await cloudSource.fingerprint();

      final service = SyncBundleKeyService(
        secureStore: localStore,
        cloudStore: _MemoryCloudSyncBundleKeyStore(cloudBackupCode),
        keyFactory: () => List<int>.filled(32, 3),
      );

      expect(await service.fingerprint(), cloudFingerprint);
    },
  );

  test(
    'SyncBundleKeyService publishes local key when cloud is empty',
    () async {
      final cloudStore = _MemoryCloudSyncBundleKeyStore();
      final service = SyncBundleKeyService(
        secureStore: MemorySecureKeyValueStore(),
        cloudStore: cloudStore,
        keyFactory: () => List<int>.generate(32, (index) => index + 7),
      );

      final backupCode = await service.exportBackupCode();

      expect(cloudStore.backupCode, backupCode);
    },
  );

  test(
    'local archive export excludes generated notes and hidden vaults',
    () async {
      SharedPreferences.setMockInitialValues({});
      final secureStore = MemorySecureKeyValueStore();
      final encryptionService = EncryptionService(random: Random(82));
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
      final container = ProviderContainer(
        overrides: [
          secureKeyValueStoreProvider.overrideWithValue(secureStore),
          encryptionServiceProvider.overrideWithValue(encryptionService),
          masterKeyServiceProvider.overrideWithValue(masterKeyService),
          profileDataKeyServiceProvider.overrideWithValue(
            profileDataKeyService,
          ),
          encryptedNoteDatabaseProvider.overrideWithValue(database),
          encryptedNoteStoreProvider.overrideWithValue(
            EncryptedNoteStore(
              encryptionService: encryptionService,
              masterKeyService: masterKeyService,
              profileDataKeyService: profileDataKeyService,
              database: database,
              directoryProvider: () async => Directory.systemTemp,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(database.close);

      final notesController = container.read(notesControllerProvider.notifier);
      await notesController.restoreCompleted;
      await profileDataKeyService.configureProfile(
        vaultId: legacyPrivateVaultId,
        password: 'private-pass',
      );
      await notesController.upsert(
        NoteEntry(
          id: 'user-note',
          vaultId: 'everyday',
          title: 'User note',
          body: '',
          createdAt: DateTime(2026, 5, 9, 9, 0),
        ),
      );
      await notesController.upsert(
        NoteEntry(
          id: 'seed-demo',
          vaultId: 'everyday',
          title: 'Demo note',
          body: '',
          createdAt: DateTime(2026, 5, 9, 8, 0),
          deviceId: 'seeded-device',
        ),
      );
      await notesController.upsert(
        NoteEntry(
          id: 'private-note',
          vaultId: legacyPrivateVaultId,
          title: 'Private note',
          body: '',
          createdAt: DateTime(2026, 5, 9, 7, 0),
        ),
      );

      final archive = await container
          .read(syncTransferControllerProvider.notifier)
          .exportLocalArchive(vaultIds: {'everyday'});
      final decoded = ZipDecoder().decodeBytes(archive.bytes);
      final notesJson =
          decoded.files.firstWhere((file) => file.name == 'notes.json').content
              as List<int>;
      final notes = (jsonDecode(utf8.decode(notesJson))['notes'] as List)
          .cast<Map>()
          .map((entry) => entry['id'])
          .toList(growable: false);

      expect(archive.noteCount, 1);
      expect(notes, ['user-note']);
    },
  );

  test(
    'SyncBundleKeyService previews imported backup code fingerprint',
    () async {
      final sourceService = SyncBundleKeyService(
        secureStore: MemorySecureKeyValueStore(),
        keyFactory: () => List<int>.generate(32, (index) => index + 3),
      );
      final backupCode = await sourceService.exportBackupCode();

      final targetService = SyncBundleKeyService(
        secureStore: MemorySecureKeyValueStore(),
        keyFactory: () => List<int>.generate(32, (index) => 255 - index),
      );

      expect(
        targetService.previewBackupCodeFingerprint(backupCode),
        await sourceService.fingerprint(),
      );
    },
  );

  test('SyncBundleKeyService rejects malformed backup code', () async {
    final service = SyncBundleKeyService(
      secureStore: MemorySecureKeyValueStore(),
      keyFactory: () => List<int>.generate(32, (index) => index),
    );

    expect(
      () => service.importBackupCode('invalid-sync-key'),
      throwsFormatException,
    );
  });

  test('NotesController can replace state from sync snapshot', () async {
    SharedPreferences.setMockInitialValues({});
    final tempDirectory = await Directory.systemTemp.createTemp(
      'himemo-sync-apply-',
    );
    final secureStore = MemorySecureKeyValueStore();
    final encryptionService = EncryptionService(random: Random(61));
    final masterKeyService = MasterKeyService(
      secureStore: secureStore,
      keyFactory: encryptionService.generateKeyBytes,
    );
    final noteDatabase = EncryptedNoteDatabase(
      executor: NativeDatabase.memory(),
    );
    final attachmentStore = EncryptedAttachmentStore(
      encryptionService: encryptionService,
      masterKeyService: masterKeyService,
      directoryProvider: () async => tempDirectory,
      sharedPreferencesProvider: SharedPreferences.getInstance,
    );
    final oldAttachmentPath = await attachmentStore.storeEncryptedPayload(
      encodedPayload: '{"cipherText":"legacy"}',
      type: AttachmentType.photo,
      fileNameHint: 'legacy.jpg',
    );
    expect(oldAttachmentPath, isNotNull);
    final seededAttachmentPath = oldAttachmentPath!;
    final container = ProviderContainer(
      overrides: [
        secureKeyValueStoreProvider.overrideWithValue(secureStore),
        encryptionServiceProvider.overrideWithValue(encryptionService),
        masterKeyServiceProvider.overrideWithValue(masterKeyService),
        encryptedNoteDatabaseProvider.overrideWithValue(noteDatabase),
        encryptedNoteStoreProvider.overrideWithValue(
          EncryptedNoteStore(
            encryptionService: encryptionService,
            masterKeyService: masterKeyService,
            database: noteDatabase,
            directoryProvider: () async => tempDirectory,
            sharedPreferencesProvider: SharedPreferences.getInstance,
          ),
        ),
        encryptedAttachmentStoreProvider.overrideWithValue(attachmentStore),
        homeRepositoryProvider.overrideWithValue(
          _AttachmentSeedRepository(seededAttachmentPath),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(noteDatabase.close);

    final controller = container.read(notesControllerProvider.notifier);
    await controller.seedIfEmpty();
    await controller.replaceFromSync([
      NoteEntry(
        id: 'imported',
        vaultId: 'everyday',
        title: 'Imported',
        body: 'From remote bundle',
        createdAt: DateTime(2026, 4, 12, 18, 0),
        attachments: const [],
      ),
    ]);

    expect(
      container.read(notesControllerProvider).map((note) => note.id).toList(),
      ['imported'],
    );
    expect(await File(seededAttachmentPath).exists(), isFalse);

    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test(
    'NotesController merges sync changes without replacing local state',
    () async {
      SharedPreferences.setMockInitialValues({});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'himemo-sync-merge-',
      );
      final secureStore = MemorySecureKeyValueStore();
      final encryptionService = EncryptionService(random: Random(62));
      final masterKeyService = MasterKeyService(
        secureStore: secureStore,
        keyFactory: encryptionService.generateKeyBytes,
      );
      final noteDatabase = EncryptedNoteDatabase(
        executor: NativeDatabase.memory(),
      );
      final container = ProviderContainer(
        overrides: [
          secureKeyValueStoreProvider.overrideWithValue(secureStore),
          encryptionServiceProvider.overrideWithValue(encryptionService),
          masterKeyServiceProvider.overrideWithValue(masterKeyService),
          encryptedNoteDatabaseProvider.overrideWithValue(noteDatabase),
          encryptedNoteStoreProvider.overrideWithValue(
            EncryptedNoteStore(
              encryptionService: encryptionService,
              masterKeyService: masterKeyService,
              database: noteDatabase,
              directoryProvider: () async => tempDirectory,
              sharedPreferencesProvider: SharedPreferences.getInstance,
            ),
          ),
          homeRepositoryProvider.overrideWithValue(_MinimalHomeRepository()),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(noteDatabase.close);

      final controller = container.read(notesControllerProvider.notifier);
      await controller.mergeFromSync([
        PreparedSyncNote(
          action: PendingNoteChangeAction.upsert,
          note: NoteEntry(
            id: 'remote-a',
            vaultId: 'everyday',
            title: 'Remote A',
            body: 'From another device',
            createdAt: DateTime(2026, 4, 13, 9, 0),
            updatedAt: DateTime(2026, 4, 13, 9, 5),
            revision: 2,
            contentHash: 'remote-a-v2',
          ),
        ),
        PreparedSyncNote(
          action: PendingNoteChangeAction.upsert,
          note: NoteEntry(
            id: 'remote-b',
            vaultId: 'everyday',
            title: 'Remote B',
            body: 'Also from remote',
            createdAt: DateTime(2026, 4, 13, 10, 0),
            contentHash: 'remote-b-v1',
          ),
        ),
      ]);

      expect(
        container.read(notesControllerProvider).map((note) => note.id),
        containsAll(['remote-a', 'remote-b']),
      );
      expect(
        container
            .read(notesControllerProvider)
            .singleWhere((note) => note.id == 'remote-a')
            .syncState,
        NoteSyncState.synced,
      );

      await controller.mergeFromSync([
        PreparedSyncNote(
          action: PendingNoteChangeAction.delete,
          note: NoteEntry(
            id: 'remote-b',
            vaultId: 'everyday',
            title: 'Remote B',
            body: 'Deleted elsewhere',
            createdAt: DateTime(2026, 4, 13, 10, 0),
            updatedAt: DateTime(2026, 4, 13, 10, 30),
            deletedAt: DateTime(2026, 4, 13, 10, 30),
            revision: 2,
            contentHash: 'remote-b-delete',
          ),
        ),
      ]);

      expect(
        container
            .read(visibleNotesProvider)
            .any((note) => note.id == 'remote-b'),
        isFalse,
      );

      await controller.upsert(
        NoteEntry(
          id: 'remote-a',
          vaultId: 'everyday',
          title: 'Local edit',
          body: 'Pending local change',
          createdAt: DateTime(2026, 4, 13, 9, 0),
        ),
      );
      await controller.mergeFromSync([
        PreparedSyncNote(
          action: PendingNoteChangeAction.upsert,
          note: NoteEntry(
            id: 'remote-a',
            vaultId: 'everyday',
            title: 'Remote competing edit',
            body: 'Remote changed too',
            createdAt: DateTime(2026, 4, 13, 9, 0),
            updatedAt: DateTime(2026, 4, 13, 11, 0),
            revision: 4,
            contentHash: 'remote-a-v4',
          ),
        ),
      ]);

      final conflicted = container
          .read(notesControllerProvider)
          .singleWhere((note) => note.id == 'remote-a');
      expect(conflicted.title, 'Local edit');
      expect(conflicted.syncState, NoteSyncState.conflict);
      expect(await noteDatabase.loadPendingChanges(), isEmpty);

      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    },
  );

  test('SyncBundleStateStore persists remote and apply metadata', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncBundleStateStore(
      sharedPreferencesProvider: SharedPreferences.getInstance,
    );
    final remote = RemoteSyncBundleStatus(
      fileId: 'file-1',
      fileName: 'himemo_sync_bundle.enc',
      modifiedAt: DateTime(2026, 4, 12, 19, 0),
      deviceId: 'remote-device',
    );

    await store.recordRemoteStatus(remote);
    await store.recordApply(remote);
    final restored = await store.read();

    expect(restored.lastRemoteFileId, 'file-1');
    expect(restored.lastRemoteDeviceId, 'remote-device');
    expect(restored.lastRemoteModifiedAt, DateTime(2026, 4, 12, 19, 0));
    expect(restored.lastAppliedAt, isNotNull);
  });

  test(
    'remote bundle apply check detects changed file id despite clock time',
    () {
      final bundleState = SyncBundleState(
        lastRemoteFileId: 'remote-old',
        lastRemoteModifiedAt: DateTime(2026, 5, 9, 10, 0),
        lastAppliedAt: DateTime(2026, 5, 9, 10, 5),
        lastUploadedAt: DateTime(2026, 5, 9, 10, 6),
      );

      expect(
        remoteBundleNeedsApplyForSync(
          RemoteSyncBundleStatus(
            fileId: 'remote-new',
            fileName: 'latest_sync_bundle.enc',
            modifiedAt: DateTime(2026, 5, 9, 10, 0),
          ),
          bundleState,
        ),
        isTrue,
      );
      expect(
        remoteBundleNeedsApplyForSync(
          RemoteSyncBundleStatus(
            fileId: 'remote-old',
            fileName: 'latest_sync_bundle.enc',
            modifiedAt: DateTime(2026, 5, 9, 10, 10),
          ),
          bundleState,
        ),
        isFalse,
      );
    },
  );

  test(
    'assessSyncConflict reports newer remote bundle against pending local queue',
    () {
      final assessment = assessSyncConflict(
        googleDriveSelected: true,
        queue: const SyncQueueSummary(totalChanges: 2, upserts: 1, deletes: 1),
        remoteStatus: RemoteSyncBundleStatus(
          fileId: 'remote-1',
          fileName: 'himemo_sync_bundle.enc',
          modifiedAt: DateTime(2026, 4, 12, 20, 0),
          deviceId: 'other-device',
        ),
        bundleState: SyncBundleState(
          lastRemoteFileId: 'remote-0',
          lastRemoteModifiedAt: DateTime(2026, 4, 12, 19, 0),
          lastRemoteDeviceId: 'device-a',
          lastUploadedAt: DateTime(2026, 4, 12, 19, 15),
        ),
      );

      expect(assessment.hasConflict, isTrue);
      expect(assessment.message, isNotNull);
    },
  );

  test('assessSyncConflict ignores matching device or stale remote bundle', () {
    final assessment = assessSyncConflict(
      googleDriveSelected: true,
      queue: const SyncQueueSummary(totalChanges: 1, upserts: 1, deletes: 0),
      remoteStatus: RemoteSyncBundleStatus(
        fileId: 'remote-1',
        fileName: 'himemo_sync_bundle.enc',
        modifiedAt: DateTime(2026, 4, 12, 18, 0),
        deviceId: 'device-a',
      ),
      bundleState: SyncBundleState(
        lastRemoteFileId: 'remote-1',
        lastRemoteModifiedAt: DateTime(2026, 4, 12, 18, 0),
        lastRemoteDeviceId: 'device-a',
        lastAppliedAt: DateTime(2026, 4, 12, 19, 0),
      ),
    );

    expect(assessment.hasConflict, isFalse);
    expect(assessment.message, isNull);
  });

  test('buildSyncBundlePreview summarizes add, update, and removal counts', () {
    final preview = buildSyncBundlePreview(
      decodedBundle: {
        'deviceId': 'remote-device',
        'exportedAt': '2026-04-12T20:15:00.000',
        'notes': [
          {
            'action': 'upsert',
            'note': NoteEntry(
              id: 'existing',
              vaultId: 'everyday',
              title: 'Updated title',
              body: 'Updated body',
              createdAt: DateTime(2026, 4, 12, 10, 0),
              revision: 3,
              contentHash: 'hash-new',
            ).toJson(),
          },
          {
            'action': 'upsert',
            'note': NoteEntry(
              id: 'added',
              vaultId: 'everyday',
              title: 'Added note',
              body: 'Fresh from remote',
              createdAt: DateTime(2026, 4, 12, 11, 0),
            ).toJson(),
          },
          {
            'action': 'delete',
            'note': NoteEntry(
              id: 'removed',
              vaultId: 'everyday',
              title: 'Remote removed',
              body: 'Deleted on another device',
              createdAt: DateTime(2026, 4, 12, 9, 0),
              deletedAt: DateTime(2026, 4, 12, 20, 0),
            ).toJson(),
          },
        ],
        'attachments': [
          {'id': 'existing-0'},
        ],
      },
      currentNotes: [
        NoteEntry(
          id: 'existing',
          vaultId: 'everyday',
          title: 'Old title',
          body: 'Old body',
          createdAt: DateTime(2026, 4, 12, 10, 0),
          revision: 1,
          contentHash: 'hash-old',
        ),
        NoteEntry(
          id: 'removed',
          vaultId: 'everyday',
          title: 'Local only',
          body: 'Will be removed',
          createdAt: DateTime(2026, 4, 12, 9, 0),
        ),
      ],
    );

    expect(preview.deviceId, 'remote-device');
    expect(preview.noteCount, 3);
    expect(preview.attachmentCount, 1);
    expect(preview.addedCount, 1);
    expect(preview.updatedCount, 1);
    expect(preview.removedCount, 1);
    expect(preview.privateVaultNoteCount, 0);
    expect(preview.sampleTitles, ['Updated title', 'Added note']);
    expect(preview.addedTitles, ['Added note']);
    expect(preview.updatedTitles, ['Updated title']);
    expect(preview.removedTitles, ['Local only']);
  });
}

class _SingleNoteRepository implements HomeRepository {
  @override
  List<UnlockIdentity> get identities => const <UnlockIdentity>[];

  @override
  List<NoteEntry> get seededNotes => [
    NoteEntry(
      id: 'tracked',
      vaultId: 'everyday',
      title: 'Tracked',
      body: 'Tracked body',
      createdAt: DateTime(2026, 4, 12, 12, 0),
      updatedAt: DateTime(2026, 4, 12, 12, 0),
      deviceId: 'seeded-device',
      contentHash: 'tracked-hash',
      syncState: NoteSyncState.synced,
      attachments: const [
        NoteAttachment(
          type: AttachmentType.photo,
          label: 'proof.jpg',
          filePath: 'secure-attachment://old',
        ),
      ],
    ),
  ];

  @override
  List<VaultBucket> get vaults => const <VaultBucket>[
    VaultBucket(id: 'everyday', name: 'Notes', description: 'Test vault'),
  ];
}

class _AttachmentSeedRepository implements HomeRepository {
  const _AttachmentSeedRepository(this.attachmentPath);

  final String attachmentPath;

  @override
  List<UnlockIdentity> get identities => const <UnlockIdentity>[];

  @override
  List<NoteEntry> get seededNotes => [
    NoteEntry(
      id: 'seeded-old',
      vaultId: 'everyday',
      title: 'Seeded old',
      body: 'Old attachment note',
      createdAt: DateTime(2026, 4, 12, 11, 0),
      attachments: [
        NoteAttachment(
          type: AttachmentType.photo,
          label: 'legacy.jpg',
          filePath: attachmentPath,
        ),
      ],
    ),
  ];

  @override
  List<VaultBucket> get vaults => const <VaultBucket>[
    VaultBucket(id: 'everyday', name: 'Notes', description: 'Test vault'),
  ];
}

class _MinimalHomeRepository implements HomeRepository {
  @override
  List<UnlockIdentity> get identities => const <UnlockIdentity>[
    UnlockIdentity(
      id: 'daily',
      name: 'Daily View',
      tagline: 'Minimal test identity',
      lockLabel: 'PIN',
      visibleVaultIds: ['everyday'],
      accentHex: 0xFF6B8798,
      warning: 'Test only',
    ),
  ];

  @override
  List<NoteEntry> get seededNotes => const <NoteEntry>[];

  @override
  List<VaultBucket> get vaults => const <VaultBucket>[
    VaultBucket(id: 'everyday', name: 'Notes', description: 'Test vault'),
  ];
}

class _TrackingEncryptedAttachmentStore extends EncryptedAttachmentStore {
  _TrackingEncryptedAttachmentStore({
    required super.encryptionService,
    required super.masterKeyService,
    required super.directoryProvider,
    required super.sharedPreferencesProvider,
  });

  final List<String> deletedReferences = <String>[];

  @override
  Future<void> deleteAttachment(String storedReference) async {
    deletedReferences.add(storedReference);
  }
}

class _MemoryCloudSyncBundleKeyStore implements CloudSyncBundleKeyStore {
  _MemoryCloudSyncBundleKeyStore([this.backupCode]);

  String? backupCode;

  @override
  Future<String?> readBackupCode() async => backupCode;

  @override
  Future<void> writeBackupCode(String backupCode) async {
    this.backupCode = backupCode;
  }
}
