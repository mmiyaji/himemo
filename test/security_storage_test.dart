import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
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

    test(
      'quarantines malformed legacy notes and keeps fallback notes',
      () async {
        await prefs.setString('notes.entries.v1', '{"not":"a note list"}');
        final fallback = [
          NoteEntry(
            id: 'fallback-note',
            vaultId: 'everyday',
            title: 'Fallback survives',
            body: 'Malformed legacy data should not block startup.',
            createdAt: DateTime(2026, 5, 28, 10, 0),
          ),
        ];

        final restored = await noteStore.load(fallbackNotes: fallback);

        expect(restored, fallback);
        expect(prefs.getString('notes.entries.v1'), isNull);
        expect(
          prefs.getString('notes.entries.v1.corrupt'),
          '{"not":"a note list"}',
        );
        expect(await database.loadAll(), isEmpty);
      },
    );

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
      'normal saves preserve omitted private profile snapshots when guarded',
      () async {
        final tempDirectory = await Directory.systemTemp.createTemp(
          'himemo-profile-key-preserve-',
        );
        final database = EncryptedNoteDatabase(
          executor: NativeDatabase.memory(),
        );
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
        const vaultId = 'private_profile:a';
        await profileKeys.configureProfile(
          vaultId: vaultId,
          password: 'correct horse battery staple',
        );
        final store = EncryptedNoteStore(
          encryptionService: encryptionService,
          masterKeyService: masterKeyService,
          profileDataKeyService: profileKeys,
          database: database,
          directoryProvider: () async => tempDirectory,
          sharedPreferencesProvider: () async => prefs,
        );
        final privateNote = NoteEntry(
          id: 'private-a',
          vaultId: vaultId,
          title: 'Secret profile title',
          body: 'Secret profile body',
          createdAt: DateTime(2026, 5, 6, 8, 0),
        );
        final normalNote = NoteEntry(
          id: 'normal-a',
          vaultId: 'everyday',
          title: 'Normal title',
          body: 'Normal body',
          createdAt: DateTime(2026, 5, 6, 9, 0),
        );

        await store.save([privateNote, normalNote]);
        profileKeys.lockProfile(vaultId);
        await store.save([normalNote], preserveOmittedPrivateNotes: true);

        final guarded = await store.load(fallbackNotes: const []);
        expect(
          guarded.map((note) => note.id),
          containsAll(['normal-a', 'private-a']),
        );
        expect(
          guarded.singleWhere((note) => note.id == 'private-a').title,
          'Locked private note',
        );

        await store.save([normalNote]);
        final explicitlyReplaced = await store.load(fallbackNotes: const []);
        expect(explicitlyReplaced.map((note) => note.id), ['normal-a']);
      },
    );

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

  group('EncryptedNoteDatabase edge paths', () {
    late EncryptedNoteDatabase database;

    setUp(() {
      database = EncryptedNoteDatabase(executor: NativeDatabase.memory());
    });

    tearDown(() => database.close());

    test('loads records, pending fallbacks, and storage sizes', () async {
      final createdAt = DateTime(2026, 6, 12, 8, 0);
      final updatedAt = DateTime(2026, 6, 12, 9, 0);
      final deletedAt = DateTime(2026, 6, 12, 10, 0);
      final plain = EncryptedNoteRecord(
        id: 'plain',
        vaultId: 'everyday',
        encryptedPayload: 'plain-payload',
        createdAt: createdAt,
        updatedAt: updatedAt,
        deletedAt: null,
        isPinned: false,
        revision: 2,
        syncState: NoteSyncState.pendingUpload,
        deviceId: 'device-a',
        contentHash: 'hash-plain',
      );
      final pinned = EncryptedNoteRecord(
        id: 'pinned',
        vaultId: 'private_profile:db',
        encryptedPayload: 'pinned-payload',
        createdAt: createdAt.subtract(const Duration(hours: 1)),
        updatedAt: null,
        deletedAt: deletedAt,
        isPinned: true,
        revision: 3,
        syncState: NoteSyncState.pendingDelete,
        deviceId: null,
        contentHash: null,
      );

      await database.replaceAll(
        notes: [plain, pinned],
        attachments: const [
          EncryptedAttachmentRecord(
            noteId: 'plain',
            position: 1,
            encryptedPayload: 'attachment-1',
          ),
          EncryptedAttachmentRecord(
            noteId: 'plain',
            position: 0,
            encryptedPayload: 'attachment-0',
          ),
        ],
        pendingChanges: [
          PendingNoteChangeRecord(
            noteId: 'plain',
            vaultId: 'everyday',
            revision: 2,
            action: PendingNoteChangeAction.upsert,
            queuedAt: updatedAt,
            contentHash: 'hash-plain',
          ),
          PendingNoteChangeRecord(
            noteId: 'pinned',
            vaultId: 'private_profile:db',
            revision: 3,
            action: PendingNoteChangeAction.delete,
            queuedAt: deletedAt,
            deletedAt: deletedAt,
          ),
        ],
      );

      final snapshots = await database.loadAll();
      expect(snapshots.map((snapshot) => snapshot.note.id), [
        'pinned',
        'plain',
      ]);
      expect(snapshots.last.attachments.map((record) => record.position), [
        0,
        1,
      ]);
      expect(await database.storagePayloadSizeBytes(), greaterThan(0));
      expect(await database.existingNoteIds({'plain', 'missing'}), {'plain'});

      await database.customStatement(
        "UPDATE encrypted_notes SET sync_state = 'legacy' WHERE id = ?",
        ['plain'],
      );
      await database.customStatement(
        "UPDATE pending_note_changes SET sync_action = 'legacy' "
        'WHERE note_id = ?',
        ['plain'],
      );

      final fallbackSnapshot = (await database.loadAll()).singleWhere(
        (snapshot) => snapshot.note.id == 'plain',
      );
      expect(fallbackSnapshot.note.syncState, NoteSyncState.localOnly);
      final fallbackPending = (await database.loadPendingChanges()).singleWhere(
        (change) => change.noteId == 'plain',
      );
      expect(fallbackPending.action, PendingNoteChangeAction.upsert);
    });

    test('deletes vault data and handles empty set guards', () async {
      final now = DateTime(2026, 6, 12, 11, 0);

      expect(await database.existingNoteIds(const <String>{}), isEmpty);
      await database.deletePendingChangesByIds(const <String>{});
      await database.markNotesSyncedByIds(const <String>{});

      await database.replaceAll(
        notes: [
          EncryptedNoteRecord(
            id: 'private-note',
            vaultId: 'private_profile:db',
            encryptedPayload: 'private-payload',
            createdAt: now,
            updatedAt: now,
            deletedAt: null,
            isPinned: false,
            revision: 1,
            syncState: NoteSyncState.pendingUpload,
            deviceId: null,
            contentHash: 'hash-private',
          ),
        ],
        attachments: const [
          EncryptedAttachmentRecord(
            noteId: 'private-note',
            position: 0,
            encryptedPayload: 'attachment',
          ),
        ],
        pendingChanges: [
          PendingNoteChangeRecord(
            noteId: 'private-note',
            vaultId: 'private_profile:db',
            revision: 1,
            action: PendingNoteChangeAction.upsert,
            queuedAt: now,
          ),
          PendingNoteChangeRecord(
            noteId: 'orphan-pending',
            vaultId: 'private_profile:missing',
            revision: 1,
            action: PendingNoteChangeAction.delete,
            queuedAt: now,
            deletedAt: now,
          ),
        ],
      );

      await database.markNotesSyncedByIds({'private-note'});
      expect(
        (await database.loadAll()).single.note.syncState,
        NoteSyncState.synced,
      );
      await database.deletePendingChangesByIds({'private-note'});
      expect(
        (await database.loadPendingChanges()).map((change) => change.noteId),
        ['orphan-pending'],
      );

      await database.deleteNotesByVaultId('private_profile:missing');
      expect(await database.loadPendingChanges(), isEmpty);

      await database.replaceAll(
        notes: [
          EncryptedNoteRecord(
            id: 'private-note',
            vaultId: 'private_profile:db',
            encryptedPayload: 'private-payload',
            createdAt: now,
            updatedAt: now,
            deletedAt: null,
            isPinned: false,
            revision: 2,
            syncState: NoteSyncState.pendingUpload,
            deviceId: null,
            contentHash: null,
          ),
        ],
        attachments: const [
          EncryptedAttachmentRecord(
            noteId: 'private-note',
            position: 0,
            encryptedPayload: 'attachment',
          ),
        ],
        pendingChanges: [
          PendingNoteChangeRecord(
            noteId: 'private-note',
            vaultId: 'private_profile:db',
            revision: 2,
            action: PendingNoteChangeAction.upsert,
            queuedAt: now,
          ),
        ],
      );
      await database.deleteNotesByVaultId('private_profile:db');
      expect(await database.loadAll(), isEmpty);
      expect(await database.loadPendingChanges(), isEmpty);

      await database.replaceAll(
        notes: const [],
        attachments: const [],
        pendingChanges: const [],
      );
      expect(await database.storagePayloadSizeBytes(), 0);
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
      final rawContents = await encryptedFile.readAsBytes();
      expect(rawContents, isNot(containsAllInOrder([1, 2, 3])));
      expect(String.fromCharCodes(rawContents.take(4)), 'HMA2');

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
      'reports payload diagnostics for missing native attachments',
      () async {
        final missingReference = path.join(
          tempDirectory.path,
          'attachments',
          'missing-photo.png.enc',
        );

        final diagnostics = await attachmentStore.storedPayloadDiagnostics(
          missingReference,
        );

        expect(diagnostics['payloadLocation'], 'file');
        expect(diagnostics['originalFileExists'], isFalse);
        expect(diagnostics['resolvedFileExists'], isFalse);
        expect(diagnostics['resolvedFileRef'], 'missing-photo.png.enc');
        expect(diagnostics['encryptedFileBytes'], isNull);
        expect(diagnostics['encryptedPayloadChars'], isNull);
      },
    );

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

    test(
      'keeps attachments retained by migrated basename references',
      () async {
        expect(
          await attachmentStore.deleteUnreferencedAttachments(const <String>{}),
          0,
        );

        final source = File(
          '${tempDirectory.path}${Platform.pathSeparator}migrated.jpg',
        );
        await source.writeAsBytes(const [21, 22, 23], flush: true);
        final storedReference = await attachmentStore.storeAttachment(
          XFile(source.path, name: 'migrated.jpg'),
          type: AttachmentType.photo,
        );
        final retainedByPreviousContainer = path.join(
          tempDirectory.path,
          'old-container',
          'attachments',
          path.basename(storedReference!),
        );

        expect(
          await attachmentStore.deleteUnreferencedAttachments({
            retainedByPreviousContainer,
          }),
          0,
        );
        expect(await File(storedReference).exists(), isTrue);
      },
    );

    test('reports native payload metadata and direct payload reads', () async {
      final source = File(
        '${tempDirectory.path}${Platform.pathSeparator}metadata.png',
      );
      await source.writeAsBytes(const [31, 32, 33, 34], flush: true);
      final storedReference = await attachmentStore.storeAttachment(
        XFile(source.path, name: 'metadata.png'),
        type: AttachmentType.photo,
      );

      final estimated = await attachmentStore
          .estimateStoredAttachmentPayloadBytes(storedReference!);
      final metadata = await attachmentStore.storedPayloadMetadata(
        storedReference,
      );
      final diagnostics = await attachmentStore.storedPayloadDiagnostics(
        storedReference,
      );
      final storedPayload = await attachmentStore.readStoredPayload(
        storedReference,
      );

      expect(estimated, greaterThan(0));
      expect(metadata?.sizeBytes, estimated);
      expect(metadata?.modifiedAtMillis, isNotNull);
      expect(diagnostics['payloadLocation'], 'file');
      expect(diagnostics['originalFileExists'], isTrue);
      expect(diagnostics['resolvedFileExists'], isTrue);
      expect(diagnostics['encryptedPayloadChars'], isNull);
      expect(storedPayload, startsWith('binary:'));
      expect(await attachmentStore.storagePayloadSizeBytes(), estimated);

      await attachmentStore.deleteAttachment(storedReference);
      expect(await File(storedReference).exists(), isFalse);
      expect(prefs.getString('attachments.vault.$storedReference'), isNull);
    });

    test('materializes raw bytes and ignores empty cleanup requests', () async {
      expect(
        await attachmentStore.materializeDecryptedBytes(
          const [],
          type: AttachmentType.file,
        ),
        isNull,
      );

      await attachmentStore.markMaterializedFileForCleanup(
        '',
        deleteAfter: DateTime.utc(2026, 6, 12),
      );
      await attachmentStore.markMaterializedFileForCleanup(
        path.join(tempDirectory.path, 'missing.tmp'),
        deleteAfter: DateTime.utc(2026, 6, 12),
      );

      final unnamed = await attachmentStore.materializeDecryptedBytes(const [
        41,
        42,
      ], type: AttachmentType.file);
      final named = await attachmentStore.materializeDecryptedBytes(
        const [43, 44, 45],
        type: AttachmentType.photo,
        preferredFileName: 'named.jpg',
      );

      expect(path.basename(unnamed!), endsWith('.bin'));
      expect(path.basename(named!), endsWith('.jpg'));
      expect(await File(unnamed).readAsBytes(), const [41, 42]);
      expect(await File(named).readAsBytes(), const [43, 44, 45]);

      await attachmentStore.deleteMaterializedFile(unnamed);
      expect(await File(unnamed).exists(), isFalse);
      expect(await attachmentStore.clearMaterializedCache(), 3);
    });

    test(
      'protects attachment vault metadata without unnecessary rewrites',
      () async {
        final source = File(
          '${tempDirectory.path}${Platform.pathSeparator}protect.jpg',
        );
        await source.writeAsBytes(const [51, 52, 53], flush: true);
        final storedReference = await attachmentStore.storeAttachment(
          XFile(source.path, name: 'protect.jpg'),
          type: AttachmentType.photo,
        );

        await attachmentStore.protectAttachmentForVault(
          storedReference!,
          type: AttachmentType.photo,
          vaultId: 'everyday',
        );
        expect(
          await attachmentStore.readAttachment(
            storedReference,
            type: AttachmentType.photo,
          ),
          const [51, 52, 53],
        );

        await attachmentStore.protectAttachmentForVault(
          path.join(tempDirectory.path, 'attachments', 'missing.enc'),
          type: AttachmentType.photo,
          vaultId: 'private_profile:locked',
        );
      },
    );

    test('cleans materialized files after persisted marker expires', () async {
      final source = File(
        '${tempDirectory.path}${Platform.pathSeparator}clip.mp4',
      );
      await source.writeAsBytes(const [1, 2, 3, 4], flush: true);
      final storedReference = await attachmentStore.storeAttachment(
        XFile(source.path, name: 'clip.mp4', mimeType: 'video/mp4'),
        type: AttachmentType.video,
      );
      final materializedPath = await attachmentStore.materializeDecryptedFile(
        storedReference!,
        type: AttachmentType.video,
        preferredFileName: 'clip.mp4',
      );
      expect(materializedPath, isNotNull);

      await attachmentStore.markMaterializedFileForCleanup(
        materializedPath!,
        deleteAfter: DateTime.utc(2026, 5, 13, 12),
      );

      expect(
        await attachmentStore.cleanupExpiredMaterializedFiles(
          now: DateTime.utc(2026, 5, 13, 11, 59),
        ),
        0,
      );
      expect(await File(materializedPath).exists(), isTrue);

      expect(
        await attachmentStore.cleanupExpiredMaterializedFiles(
          now: DateTime.utc(2026, 5, 13, 12),
        ),
        1,
      );
      expect(await File(materializedPath).exists(), isFalse);
      expect(
        await File('$materializedPath.himemo-delete-after').exists(),
        isFalse,
      );
    });

    test('reports and clears materialized attachment cache', () async {
      final source = File(
        '${tempDirectory.path}${Platform.pathSeparator}voice.m4a',
      );
      await source.writeAsBytes(const [11, 12, 13, 14, 15], flush: true);
      final storedReference = await attachmentStore.storeAttachment(
        XFile(source.path, name: 'voice.m4a', mimeType: 'audio/mp4'),
        type: AttachmentType.audio,
      );
      final materializedPath = await attachmentStore.materializeDecryptedFile(
        storedReference!,
        type: AttachmentType.audio,
        preferredFileName: 'voice.m4a',
      );
      expect(materializedPath, isNotNull);
      final tempPath = materializedPath!;
      final marker = File('$tempPath.himemo-delete-after');
      await marker.create(recursive: true);
      await marker.writeAsString('not-expired-yet');

      expect(await attachmentStore.materializedCacheSizeBytes(), 20);

      final deletedBytes = await attachmentStore.clearMaterializedCache();

      expect(deletedBytes, 20);
      expect(await File(tempPath).exists(), isFalse);
      expect(await marker.exists(), isFalse);
      expect(await attachmentStore.materializedCacheSizeBytes(), 0);
      expect(
        await attachmentStore.readAttachment(
          storedReference,
          type: AttachmentType.audio,
        ),
        const [11, 12, 13, 14, 15],
      );
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

  test('NotesController creates notes that only contain attachments', () async {
    SharedPreferences.setMockInitialValues({});
    final tempDirectory = await Directory.systemTemp.createTemp(
      'himemo-attachment-only-note-',
    );
    final secureStore = MemorySecureKeyValueStore();
    final encryptionService = EncryptionService(random: Random(31));
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
    final noteStore = EncryptedNoteStore(
      encryptionService: encryptionService,
      masterKeyService: masterKeyService,
      database: noteDatabase,
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
        deviceIdentityStoreProvider.overrideWithValue(
          DeviceIdentityStore(
            sharedPreferencesProvider: SharedPreferences.getInstance,
            random: Random(31),
          ),
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

    final filePath = await attachmentStore.storeAttachment(
      XFile.fromData(Uint8List.fromList([1, 2, 3, 4]), name: 'only.png'),
      type: AttachmentType.photo,
    );
    final attachment = NoteAttachment(
      type: AttachmentType.photo,
      label: 'only.png',
      filePath: filePath,
    );

    await container
        .read(notesControllerProvider.notifier)
        .upsert(
          NoteEntry(
            id: 'attachment-only',
            vaultId: 'everyday',
            title: '',
            body: '',
            createdAt: DateTime(2026, 5, 15, 9),
            attachments: [attachment],
            blocks: [
              NoteBlock(type: NoteBlockType.photo, attachment: attachment),
            ],
            editorMode: NoteEditorMode.rich,
          ),
        );

    expect(
      container.read(notesControllerProvider).single.id,
      'attachment-only',
    );
    final restored = await noteStore.load(fallbackNotes: const []);
    expect(restored.single.attachments.single.label, 'only.png');
  });

  test(
    'NotesController keeps attachment files still referenced by blocks',
    () async {
      SharedPreferences.setMockInitialValues({});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'himemo-notes-block-attachment-',
      );
      final secureStore = MemorySecureKeyValueStore();
      final encryptionService = EncryptionService(random: Random(23));
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
          encryptedAttachmentStoreProvider.overrideWithValue(
            fakeAttachmentStore,
          ),
          deviceIdentityStoreProvider.overrideWithValue(
            DeviceIdentityStore(
              sharedPreferencesProvider: SharedPreferences.getInstance,
              random: Random(2),
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
      final attachment = original.attachments.single;
      await controller.upsert(
        original.copyWith(
          attachments: const <NoteAttachment>[],
          blocks: [
            NoteBlock(type: NoteBlockType.photo, attachment: attachment),
          ],
        ),
      );

      expect(fakeAttachmentStore.deletedReferences, isEmpty);
    },
  );

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

  test('NotesController cleanup keeps attachments held in trash', () async {
    SharedPreferences.setMockInitialValues({});
    final tempDirectory = await Directory.systemTemp.createTemp(
      'himemo-trash-cleanup-',
    );
    final secureStore = MemorySecureKeyValueStore();
    final encryptionService = EncryptionService(random: Random(24));
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
        deviceIdentityStoreProvider.overrideWithValue(
          DeviceIdentityStore(
            sharedPreferencesProvider: SharedPreferences.getInstance,
            random: Random(24),
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

    final storedReference = await attachmentStore.storeAttachment(
      XFile.fromData(Uint8List.fromList([9, 8, 7, 6]), name: 'trash.png'),
      type: AttachmentType.photo,
    );
    final attachment = NoteAttachment(
      type: AttachmentType.photo,
      label: 'trash.png',
      filePath: storedReference,
    );
    final controller = container.read(notesControllerProvider.notifier);
    await controller.upsert(
      NoteEntry(
        id: 'trash-cleanup',
        vaultId: 'everyday',
        title: 'Trashed attachment',
        body: '',
        createdAt: DateTime(2026, 5, 15, 11),
        attachments: [attachment],
        blocks: [NoteBlock(type: NoteBlockType.photo, attachment: attachment)],
      ),
    );
    await controller.delete('trash-cleanup');

    expect(await controller.cleanupUnreferencedAttachments(), 0);
    expect(
      await attachmentStore.readAttachment(
        storedReference!,
        type: AttachmentType.photo,
      ),
      [9, 8, 7, 6],
    );
  });

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
    'NotesController restores trashed notes and permanent delete removes files',
    () async {
      SharedPreferences.setMockInitialValues({});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'himemo-trash-restore-',
      );
      final secureStore = MemorySecureKeyValueStore();
      final encryptionService = EncryptionService(random: Random(32));
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
      final attachmentStore = _TrackingEncryptedAttachmentStore(
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
          deviceIdentityStoreProvider.overrideWithValue(
            DeviceIdentityStore(
              sharedPreferencesProvider: SharedPreferences.getInstance,
              random: Random(32),
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
      final attachment = NoteAttachment(
        type: AttachmentType.photo,
        label: 'trash-proof.jpg',
        filePath: 'secure-attachment://trash-proof',
      );
      await controller.upsert(
        NoteEntry(
          id: 'trash-1',
          vaultId: 'everyday',
          title: 'Trash note',
          body: 'Can be restored',
          createdAt: DateTime(2026, 5, 15, 10),
          attachments: [attachment],
          blocks: [
            NoteBlock(type: NoteBlockType.photo, attachment: attachment),
          ],
        ),
      );

      await controller.delete('trash-1');
      expect(
        container
            .read(visibleNotesProvider)
            .any((note) => note.id == 'trash-1'),
        isFalse,
      );
      expect(container.read(trashedNotesProvider).single.id, 'trash-1');

      await controller.restoreFromTrash('trash-1');
      final restored = container
          .read(notesControllerProvider)
          .singleWhere((note) => note.id == 'trash-1');
      expect(restored.deletedAt, isNull);
      expect(restored.syncState, NoteSyncState.pendingUpload);
      expect(container.read(trashedNotesProvider), isEmpty);
      expect(attachmentStore.deletedReferences, isEmpty);

      await controller.delete('trash-1');
      await controller.deletePermanently('trash-1');
      expect(
        container
            .read(notesControllerProvider)
            .any((note) => note.id == 'trash-1'),
        isFalse,
      );
      expect(
        (await noteStore.load(
          fallbackNotes: const <NoteEntry>[],
        )).any((note) => note.id == 'trash-1'),
        isFalse,
      );
      expect(attachmentStore.deletedReferences, [
        'secure-attachment://trash-proof',
      ]);
    },
  );

  test('NotesController purges trash after the retention window', () async {
    SharedPreferences.setMockInitialValues({});
    final tempDirectory = await Directory.systemTemp.createTemp(
      'himemo-trash-purge-',
    );
    final secureStore = MemorySecureKeyValueStore();
    final encryptionService = EncryptionService(random: Random(33));
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
    final attachmentStore = _TrackingEncryptedAttachmentStore(
      encryptionService: encryptionService,
      masterKeyService: masterKeyService,
      directoryProvider: () async => tempDirectory,
      sharedPreferencesProvider: SharedPreferences.getInstance,
    );
    final expiredAttachment = NoteAttachment(
      type: AttachmentType.photo,
      label: 'expired.jpg',
      filePath: 'secure-attachment://expired',
    );
    await noteStore.save([
      NoteEntry(
        id: 'trash-expired',
        vaultId: 'everyday',
        title: 'Expired',
        body: 'Old trash',
        createdAt: DateTime(2026, 5, 1, 10),
        deletedAt: DateTime.now().subtract(const Duration(days: 8)),
        attachments: [expiredAttachment],
      ),
      NoteEntry(
        id: 'trash-recent',
        vaultId: 'everyday',
        title: 'Recent',
        body: 'Still restorable',
        createdAt: DateTime(2026, 5, 14, 10),
        deletedAt: DateTime.now().subtract(const Duration(days: 2)),
      ),
    ]);
    final container = ProviderContainer(
      overrides: [
        secureKeyValueStoreProvider.overrideWithValue(secureStore),
        encryptionServiceProvider.overrideWithValue(encryptionService),
        masterKeyServiceProvider.overrideWithValue(masterKeyService),
        encryptedNoteStoreProvider.overrideWithValue(noteStore),
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
    await controller.restoreCompleted;

    expect(container.read(notesControllerProvider).map((note) => note.id), [
      'trash-recent',
    ]);
    expect(container.read(trashedNotesProvider).single.id, 'trash-recent');
    expect(attachmentStore.deletedReferences, ['secure-attachment://expired']);
    expect(
      (await noteStore.load(
        fallbackNotes: const <NoteEntry>[],
      )).map((note) => note.id),
      ['trash-recent'],
    );
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
    'NotesController can requeue synced notes when sync target changes',
    () async {
      SharedPreferences.setMockInitialValues({});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'himemo-requeue-sync-',
      );
      final secureStore = MemorySecureKeyValueStore();
      final encryptionService = EncryptionService(random: Random(36));
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
              random: Random(7),
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
          id: 'synced-existing',
          vaultId: 'everyday',
          title: 'Synced existing',
          body: 'Should upload to a new provider',
          createdAt: DateTime(2026, 5, 9, 12),
        ),
      );
      await controller.markCurrentStateSynced();

      expect(await noteDatabase.loadPendingChanges(), isEmpty);

      await controller.queueCurrentStateForSync();

      final note = container
          .read(notesControllerProvider)
          .singleWhere((entry) => entry.id == 'synced-existing');
      expect(note.syncState, NoteSyncState.pendingUpload);
      final pendingChanges = await noteDatabase.loadPendingChanges();
      expect(pendingChanges, hasLength(1));
      expect(pendingChanges.single.noteId, 'synced-existing');
      expect(pendingChanges.single.action, PendingNoteChangeAction.upsert);
    },
  );

  test(
    'SyncEngine prepares sanitized snapshot without local attachment paths',
    () async {
      SharedPreferences.setMockInitialValues({});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'himemo-sync-engine-',
      );
      final targetTempDirectory = await Directory.systemTemp.createTemp(
        'himemo-sync-engine-target-',
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
        'sync-attachment-object://63d987d1c6d69751c17297f410f5b3547a65d096a8993b35bcb4f9cad054f176',
      );
      expect(
        snapshot.notes.single.note.attachments.single.filePath,
        isNot(storedAttachment),
      );
      expect(base64Decode(snapshot.attachments.single.bytesBase64), const [
        9,
        8,
        7,
        6,
      ]);
      expect(
        snapshot.attachments.single.contentHash,
        '63d987d1c6d69751c17297f410f5b3547a65d096a8993b35bcb4f9cad054f176',
      );
      expect(snapshot.attachments.single.sizeBytes, 4);
      final preparedAttachment = snapshot.notes.single.note.attachments.single;
      expect(preparedAttachment.localPayloadSizeBytes, isNotNull);
      expect(preparedAttachment.localPayloadModifiedAtMillis, isNotNull);
      expect(
        preparedAttachment.syncAttachmentContentHash,
        '63d987d1c6d69751c17297f410f5b3547a65d096a8993b35bcb4f9cad054f176',
      );
      final targetSecureStore = MemorySecureKeyValueStore();
      final targetEncryptionService = EncryptionService(random: Random(43));
      final targetMasterKeyService = MasterKeyService(
        secureStore: targetSecureStore,
        keyFactory: targetEncryptionService.generateKeyBytes,
      );
      final targetAttachmentStore = EncryptedAttachmentStore(
        encryptionService: targetEncryptionService,
        masterKeyService: targetMasterKeyService,
        directoryProvider: () async => targetTempDirectory,
        sharedPreferencesProvider: SharedPreferences.getInstance,
      );
      final targetEncryptedPayload = await targetAttachmentStore
          .encryptAttachmentBytes(
            bytes: base64Decode(snapshot.attachments.single.bytesBase64),
            type: AttachmentType.photo,
          );
      final targetStoredAttachment = await targetAttachmentStore
          .storeEncryptedPayload(
            encodedPayload: targetEncryptedPayload,
            type: AttachmentType.photo,
            fileNameHint: 'clip.jpg',
          );

      expect(targetStoredAttachment, isNotNull);
      expect(
        await targetAttachmentStore.readAttachment(
          targetStoredAttachment!,
          type: AttachmentType.photo,
        ),
        const [9, 8, 7, 6],
      );

      await database.close();
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
      if (await targetTempDirectory.exists()) {
        await targetTempDirectory.delete(recursive: true);
      }
    },
  );

  test(
    'SyncEngine preserves remote attachment object refs without local reads',
    () async {
      SharedPreferences.setMockInitialValues({});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'himemo-sync-engine-remote-ref-',
      );
      final secureStore = MemorySecureKeyValueStore();
      final encryptionService = EncryptionService(random: Random(44));
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
      final engine = SyncEngine(
        database: database,
        attachmentStore: attachmentStore,
        deviceIdentityStore: DeviceIdentityStore(
          sharedPreferencesProvider: SharedPreferences.getInstance,
          random: Random(45),
        ),
      );
      const remoteRef =
          'sync-attachment-object://513e1430ad6bd63eba1ec515317dac8dec689c74d8dd409012b448093cb64cfa';
      final queuedAt = DateTime(2026, 5, 15, 23, 45);
      final note = NoteEntry(
        id: 'remote-ref-note',
        vaultId: 'everyday',
        title: 'Remote video',
        body: 'Edited after deferred download.',
        createdAt: queuedAt,
        updatedAt: queuedAt.add(const Duration(minutes: 1)),
        revision: 3,
        syncState: NoteSyncState.pendingUpload,
        attachments: const [
          NoteAttachment(
            type: AttachmentType.video,
            label: 'IMG_5470.mov',
            filePath: remoteRef,
          ),
        ],
      );

      final snapshot = await engine.prepareSnapshot(
        [note],
        pendingChanges: [
          PendingNoteChangeRecord(
            noteId: note.id,
            vaultId: note.vaultId,
            revision: note.revision,
            action: PendingNoteChangeAction.upsert,
            queuedAt: queuedAt,
            contentHash: note.contentHash,
          ),
        ],
      );

      expect(snapshot.notes, hasLength(1));
      expect(snapshot.notes.single.note.attachments.single.filePath, remoteRef);
      expect(snapshot.attachments, isEmpty);

      await database.close();
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    },
  );

  test(
    'SyncEngine reuses unchanged local attachment metadata without reading bytes',
    () async {
      SharedPreferences.setMockInitialValues({});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'himemo-sync-engine-cached-attachment-',
      );
      final secureStore = MemorySecureKeyValueStore();
      final encryptionService = EncryptionService(random: Random(48));
      final masterKeyService = MasterKeyService(
        secureStore: secureStore,
        keyFactory: encryptionService.generateKeyBytes,
      );
      final attachmentStore = _ReadTrackingEncryptedAttachmentStore(
        encryptionService: encryptionService,
        masterKeyService: masterKeyService,
        directoryProvider: () async => tempDirectory,
        sharedPreferencesProvider: SharedPreferences.getInstance,
      );
      final source = File(
        '${tempDirectory.path}${Platform.pathSeparator}clip.mov',
      );
      await source.writeAsBytes(const [1, 3, 5, 7, 9], flush: true);
      final storedAttachment = await attachmentStore.storeAttachment(
        XFile(source.path, name: 'clip.mov'),
        type: AttachmentType.video,
      );
      final metadata = await attachmentStore.storedPayloadMetadata(
        storedAttachment!,
      );
      final database = EncryptedNoteDatabase(executor: NativeDatabase.memory());
      final engine = SyncEngine(
        database: database,
        attachmentStore: attachmentStore,
        deviceIdentityStore: DeviceIdentityStore(
          sharedPreferencesProvider: SharedPreferences.getInstance,
          random: Random(49),
        ),
      );
      const contentHash =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      final queuedAt = DateTime(2026, 5, 19, 14, 30);
      final note = NoteEntry(
        id: 'cached-local-attachment',
        vaultId: 'everyday',
        title: 'Edited text',
        body: 'Only text changed.',
        createdAt: queuedAt,
        updatedAt: queuedAt.add(const Duration(minutes: 1)),
        revision: 2,
        syncState: NoteSyncState.pendingUpload,
        attachments: [
          NoteAttachment(
            type: AttachmentType.video,
            label: 'clip.mov',
            filePath: storedAttachment,
            localPayloadSizeBytes: metadata?.sizeBytes,
            localPayloadModifiedAtMillis: metadata?.modifiedAtMillis,
            syncAttachmentContentHash: contentHash,
          ),
        ],
      );

      final snapshot = await engine.prepareSnapshot(
        [note],
        pendingChanges: [
          PendingNoteChangeRecord(
            noteId: note.id,
            vaultId: note.vaultId,
            revision: note.revision,
            action: PendingNoteChangeAction.upsert,
            queuedAt: queuedAt,
            contentHash: note.contentHash,
          ),
        ],
      );

      expect(attachmentStore.readCount, 0);
      expect(snapshot.attachments, isEmpty);
      expect(
        snapshot.notes.single.note.attachments.single.filePath,
        'sync-attachment-object://$contentHash',
      );

      await database.close();
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    },
  );

  test(
    'SyncEngine blocks upload snapshots when pending attachments are missing',
    () async {
      SharedPreferences.setMockInitialValues({});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'himemo-sync-engine-missing-',
      );
      final secureStore = MemorySecureKeyValueStore();
      final encryptionService = EncryptionService(random: Random(44));
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
      final missingPath =
          '${tempDirectory.path}${Platform.pathSeparator}attachments'
          '${Platform.pathSeparator}missing-photo.png.enc';
      final note = NoteEntry(
        id: 'sync-missing-attachment',
        vaultId: 'everyday',
        title: 'Missing attachment',
        body: 'This note should not upload without its photo.',
        createdAt: DateTime(2026, 5, 13, 17, 17),
        updatedAt: DateTime(2026, 5, 13, 17, 18),
        syncState: NoteSyncState.pendingUpload,
        attachments: [
          NoteAttachment(
            type: AttachmentType.photo,
            label: 'missing-photo.png',
            filePath: missingPath,
          ),
        ],
      );
      await noteStore.save([note]);
      final engine = SyncEngine(
        database: database,
        attachmentStore: attachmentStore,
        deviceIdentityStore: DeviceIdentityStore(
          sharedPreferencesProvider: SharedPreferences.getInstance,
          random: Random(45),
        ),
      );

      await expectLater(
        engine.prepareSnapshot([note]),
        throwsA(
          isA<SyncAttachmentMissingException>()
              .having((error) => error.noteId, 'noteId', note.id)
              .having(
                (error) => error.attachmentLabel,
                'attachmentLabel',
                'missing-photo.png',
              )
              .having((error) => error.filePath, 'filePath', missingPath),
        ),
      );

      await database.close();
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    },
  );

  test(
    'SyncEngine exports delete tombstones without reading trashed attachments',
    () async {
      SharedPreferences.setMockInitialValues({});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'himemo-sync-engine-delete-tombstone-',
      );
      final secureStore = MemorySecureKeyValueStore();
      final encryptionService = EncryptionService(random: Random(50));
      final masterKeyService = MasterKeyService(
        secureStore: secureStore,
        keyFactory: encryptionService.generateKeyBytes,
      );
      final attachmentStore = _ReadTrackingEncryptedAttachmentStore(
        encryptionService: encryptionService,
        masterKeyService: masterKeyService,
        directoryProvider: () async => tempDirectory,
        sharedPreferencesProvider: SharedPreferences.getInstance,
      );
      final source = File(
        '${tempDirectory.path}${Platform.pathSeparator}trash.mov',
      );
      await source.writeAsBytes(const [2, 4, 6, 8], flush: true);
      final storedAttachment = await attachmentStore.storeAttachment(
        XFile(source.path, name: 'trash.mov'),
        type: AttachmentType.video,
      );
      final database = EncryptedNoteDatabase(executor: NativeDatabase.memory());
      final engine = SyncEngine(
        database: database,
        attachmentStore: attachmentStore,
        deviceIdentityStore: DeviceIdentityStore(
          sharedPreferencesProvider: SharedPreferences.getInstance,
          random: Random(51),
        ),
      );
      final deletedAt = DateTime(2026, 5, 19, 14, 46);
      final note = NoteEntry(
        id: 'trashed-video-note',
        vaultId: 'everyday',
        title: 'Trashed video',
        body: 'This note was moved to trash.',
        createdAt: deletedAt.subtract(const Duration(minutes: 10)),
        updatedAt: deletedAt,
        deletedAt: deletedAt,
        revision: 3,
        syncState: NoteSyncState.pendingDelete,
        attachments: [
          NoteAttachment(
            type: AttachmentType.video,
            label: 'trash.mov',
            filePath: storedAttachment,
          ),
        ],
      );

      final snapshot = await engine.prepareSnapshot(
        [note],
        pendingChanges: [
          PendingNoteChangeRecord(
            noteId: note.id,
            vaultId: note.vaultId,
            revision: note.revision,
            action: PendingNoteChangeAction.delete,
            queuedAt: deletedAt,
            contentHash: note.contentHash,
            deletedAt: deletedAt,
          ),
        ],
      );

      expect(attachmentStore.readCount, 0);
      expect(snapshot.attachments, isEmpty);
      expect(snapshot.summary.deletes, 1);
      expect(snapshot.notes.single.action, PendingNoteChangeAction.delete);
      expect(snapshot.notes.single.note.id, note.id);
      expect(snapshot.notes.single.note.attachments, isEmpty);
      expect(snapshot.notes.single.note.deletedAt, deletedAt);

      await database.close();
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    },
  );

  test(
    'SyncEngine skips stale upserts and exports orphaned delete tombstones',
    () async {
      SharedPreferences.setMockInitialValues({});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'himemo-sync-engine-stale-',
      );
      final secureStore = MemorySecureKeyValueStore();
      final encryptionService = EncryptionService(random: Random(46));
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
      final engine = SyncEngine(
        database: database,
        attachmentStore: attachmentStore,
        deviceIdentityStore: DeviceIdentityStore(
          sharedPreferencesProvider: SharedPreferences.getInstance,
          random: Random(47),
        ),
      );
      final queuedAt = DateTime(2026, 5, 14, 3, 12);

      final snapshot = await engine.prepareSnapshot(
        const <NoteEntry>[],
        pendingChanges: [
          PendingNoteChangeRecord(
            noteId: 'missing-upsert',
            vaultId: 'everyday',
            revision: 1,
            action: PendingNoteChangeAction.upsert,
            queuedAt: queuedAt,
          ),
          PendingNoteChangeRecord(
            noteId: 'missing-delete',
            vaultId: 'everyday',
            revision: 2,
            action: PendingNoteChangeAction.delete,
            queuedAt: queuedAt,
            deletedAt: queuedAt,
          ),
        ],
      );

      expect(snapshot.summary.totalChanges, 1);
      expect(snapshot.summary.upserts, 0);
      expect(snapshot.summary.deletes, 1);
      expect(snapshot.notes.single.action, PendingNoteChangeAction.delete);
      expect(snapshot.notes.single.note.id, 'missing-delete');
      expect(snapshot.notes.single.note.deletedAt, queuedAt);

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
        attachments: [
          PreparedSyncAttachment(
            id: 'export-1-0',
            type: AttachmentType.photo,
            label: 'secret.jpg',
            bytesBase64: base64Encode(const [1, 2, 3, 4]),
            contentHash:
                '9f64a747e1b97f131fabb6b447296c9b6f0201e79fb3c5356e6c77e89b6a806a',
            sizeBytes: 4,
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
      expect(decoded?['bundleVersion'], 3);
      expect(decoded?['attachmentStorage'], 'objects');
      expect((decoded?['notes'] as List<dynamic>).length, 1);
      expect((decoded?['privateProfiles'] as List<dynamic>).length, 1);
      final decodedAttachments = decoded?['attachments'] as List<dynamic>;
      final decodedAttachment = decodedAttachments.single as Map;
      expect(decodedAttachment['contentHash'], isNotEmpty);
      expect(decodedAttachment['sizeBytes'], 4);
      expect(decodedAttachment.containsKey('bytesBase64'), isFalse);
      final attachmentObjectPayload = await bundleStore
          .writeAttachmentObjectPayload(snapshot.attachments.single);
      final decodedAttachmentObject = await bundleStore
          .readAttachmentObjectPayload(attachmentObjectPayload);
      expect(
        decodedAttachmentObject['contentHash'],
        decodedAttachment['contentHash'],
      );
      expect(
        decodedAttachmentObject['bytesBase64'],
        base64Encode(const [1, 2, 3, 4]),
      );
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
    'SecureSyncBundleStore does not create a new key when reading a bundle',
    () async {
      SharedPreferences.setMockInitialValues({});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'himemo-sync-bundle-missing-key-',
      );
      final secureStore = MemorySecureKeyValueStore();
      final encryptionService = EncryptionService(random: Random(52));
      final bundleStore = SecureSyncBundleStore(
        encryptionService: encryptionService,
        syncBundleKeyService: SyncBundleKeyService(
          secureStore: secureStore,
          keyFactory: () => List<int>.filled(32, 8),
        ),
        directoryProvider: () async => tempDirectory,
        sharedPreferencesProvider: SharedPreferences.getInstance,
      );

      final stored = await bundleStore.writeEncryptedBundlePayload(
        'not-a-readable-bundle',
        noteCount: 0,
        attachmentCount: 0,
      );
      await expectLater(
        bundleStore.readBundleJson(stored.reference),
        throwsStateError,
      );
      expect(await secureStore.read('security.sync_bundle_key.v1'), isNull);

      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    },
  );

  test(
    'SecureSyncBundleStore writes inline attachment bundle payloads',
    () async {
      SharedPreferences.setMockInitialValues({});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'himemo-sync-bundle-inline-',
      );
      final secureStore = MemorySecureKeyValueStore();
      final encryptionService = EncryptionService(random: Random(54));
      final bundleStore = SecureSyncBundleStore(
        encryptionService: encryptionService,
        syncBundleKeyService: SyncBundleKeyService(
          secureStore: secureStore,
          keyFactory: encryptionService.generateKeyBytes,
        ),
        directoryProvider: () async => tempDirectory,
        sharedPreferencesProvider: SharedPreferences.getInstance,
      );

      final stored = await bundleStore.writeBundle(
        PreparedSyncSnapshot(
          deviceId: 'inline-device',
          exportedAt: DateTime(2026, 6, 12, 15),
          summary: const SyncQueueSummary(
            totalChanges: 0,
            upserts: 0,
            deletes: 0,
          ),
          notes: const [],
          attachments: [
            PreparedSyncAttachment(
              id: 'inline-attachment',
              type: AttachmentType.file,
              label: 'inline.bin',
              bytesBase64: base64Encode(const [9, 8, 7]),
              encryptedPayload: 'encrypted-inline-payload',
              contentHash: 'inline-hash',
              sizeBytes: 3,
            ),
          ],
        ),
        inlineAttachments: true,
        bundleKind: SyncBundleKind.delta,
      );

      final bundle = await bundleStore.readBundleJson(stored.reference);
      final attachment =
          (bundle?['attachments'] as List<Object?>).single
              as Map<String, dynamic>;

      expect(stored.noteCount, 0);
      expect(stored.attachmentCount, 1);
      expect(bundle?['bundleVersion'], 2);
      expect(bundle?['bundleKind'], SyncBundleKind.delta);
      expect(bundle?.containsKey('attachmentStorage'), isFalse);
      expect(attachment['bytesBase64'], base64Encode(const [9, 8, 7]));
      expect(attachment['encryptedPayload'], 'encrypted-inline-payload');
      expect(attachment['contentHash'], 'inline-hash');
      expect(attachment['sizeBytes'], 3);

      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    },
  );

  test(
    'SecureSyncBundleStore reads stored metadata and legacy encrypted bundles',
    () async {
      SharedPreferences.setMockInitialValues({});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'himemo-sync-bundle-legacy-',
      );
      final syncSecureStore = MemorySecureKeyValueStore();
      final legacySecureStore = MemorySecureKeyValueStore();
      final encryptionService = EncryptionService(random: Random(53));
      final syncBundleKeyService = SyncBundleKeyService(
        secureStore: syncSecureStore,
        keyFactory: () => List<int>.filled(32, 1),
      );
      final legacyMasterKeyService = MasterKeyService(
        secureStore: legacySecureStore,
        keyFactory: () => List<int>.filled(32, 2),
      );
      final bundleStore = SecureSyncBundleStore(
        encryptionService: encryptionService,
        syncBundleKeyService: syncBundleKeyService,
        legacyMasterKeyService: legacyMasterKeyService,
        directoryProvider: () async => tempDirectory,
        sharedPreferencesProvider: SharedPreferences.getInstance,
      );

      expect(await bundleStore.readEncryptedBundlePayload('missing'), isNull);
      expect(await bundleStore.readBundleJson('missing'), isNull);
      expect(await bundleStore.readStoredEncryptedBundle(), isNull);

      await bundleStore.writeEncryptedBundlePayload(
        '',
        noteCount: 0,
        attachmentCount: 0,
        fileNameOverride: 'empty.enc',
      );
      expect(
        await bundleStore.readStoredEncryptedBundle(
          fileNameOverride: 'empty.enc',
        ),
        isNull,
      );

      await syncBundleKeyService.obtainOrCreate();
      final legacyKey = await legacyMasterKeyService.obtainOrCreate();
      final legacyPayload = await encryptionService.encryptJson(
        payload: {
          'bundleVersion': 1,
          'deviceId': 'legacy-device',
          'notes': [
            {
              'action': PendingNoteChangeAction.upsert.name,
              'note': NoteEntry(
                id: 'legacy-note',
                vaultId: 'everyday',
                title: 'Legacy note',
                body: 'Legacy body',
                createdAt: DateTime(2026, 6, 12, 12),
              ).toJson(),
            },
          ],
          'encryptedPrivateNotes': [
            {
              'note': {'id': 'private-legacy'},
            },
          ],
          'attachments': [
            {'id': 'legacy-attachment'},
          ],
        },
        secretKey: legacyKey,
      );
      await bundleStore.writeEncryptedBundlePayload(
        legacyPayload,
        noteCount: 0,
        attachmentCount: 0,
        fileNameOverride: 'legacy.enc',
      );

      final decoded = await bundleStore.readBundleJson(
        path.join(tempDirectory.path, 'sync_exports', 'legacy.enc'),
      );
      expect(decoded?['deviceId'], 'legacy-device');

      final stored = await bundleStore.readStoredEncryptedBundle(
        fileNameOverride: 'legacy.enc',
      );
      expect(stored?.noteCount, 2);
      expect(stored?.attachmentCount, 1);
      expect(path.basename(stored!.reference), 'legacy.enc');

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
    'ProfileDataKeyService changes, locks, and deletes profile keys',
    () async {
      final encryptionService = EncryptionService(random: Random(72));
      final secureStore = MemorySecureKeyValueStore();
      final masterKey = MasterKeyService(
        secureStore: secureStore,
        keyFactory: encryptionService.generateKeyBytes,
      );
      final service = ProfileDataKeyService(
        secureStore: secureStore,
        encryptionService: encryptionService,
        normalMasterKeyService: masterKey,
      );
      const vaultId = 'private_profile:password-change';

      expect(await service.keyForVault('everyday'), isA<SecretKey>());
      expect(
        await service.changeProfilePassword(
          vaultId: vaultId,
          newPassword: 'missing-key',
        ),
        isFalse,
      );

      await service.configureProfile(vaultId: vaultId, password: 'old-pass');
      expect(service.isProfileUnlocked(vaultId), isTrue);
      expect(
        await service.changeProfilePassword(
          vaultId: vaultId,
          newPassword: 'new-pass',
        ),
        isTrue,
      );

      service.lockProfile(vaultId);
      expect(service.isProfileUnlocked(vaultId), isFalse);
      expect(
        await service.unlockProfile(vaultId: vaultId, password: 'old-pass'),
        isFalse,
      );
      expect(
        await service.unlockProfile(vaultId: vaultId, password: 'new-pass'),
        isTrue,
      );

      service.lockAllPrivateProfiles();
      expect(service.isProfileUnlocked(vaultId), isFalse);

      await service.deleteProfileKey(vaultId);
      expect(await service.exportWrappedProfileKey(vaultId), isNull);
      expect(
        await service.unlockProfile(vaultId: vaultId, password: 'new-pass'),
        isFalse,
      );
    },
  );

  test('ProfileDataKeyService skips invalid wrapped key imports', () async {
    final encryptionService = EncryptionService(random: Random(73));
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
    const vaultId = 'private_profile:import-valid';

    expect(await source.exportWrappedProfileKey('everyday'), isNull);
    expect(await source.exportWrappedProfileKey(vaultId), isNull);
    await source.configureProfile(vaultId: vaultId, password: 'profile-pass');
    final exported = await source.exportWrappedProfileKeys([
      vaultId,
      vaultId,
      'everyday',
    ]);
    expect(exported, hasLength(1));

    final invalidImports = [
      null,
      'not-a-map',
      {'vaultId': 'everyday'},
      {'vaultId': 'private_profile:bad'},
      {
        'vaultId': 'private_profile:bad',
        'version': 2,
        'kdf': 'pbkdf2-sha256',
        'salt': 'salt',
        'wrappedDataKey': 'wrapped',
      },
      {
        'vaultId': 'private_profile:bad',
        'version': 1,
        'kdf': 'argon2',
        'salt': 'salt',
        'wrappedDataKey': 'wrapped',
      },
      {
        'vaultId': 'private_profile:bad',
        'version': 1,
        'kdf': 'pbkdf2-sha256',
        'salt': '',
        'wrappedDataKey': 'wrapped',
      },
      {
        'vaultId': 'private_profile:bad',
        'version': 1,
        'kdf': 'pbkdf2-sha256',
        'salt': 'salt',
        'wrappedDataKey': '',
      },
    ];
    expect(await target.importWrappedProfileKeys(invalidImports), 0);

    expect(await target.importWrappedProfileKeys(exported), 1);
    expect(await target.importWrappedProfileKeys(exported), 0);
    expect(await target.importWrappedProfileKeys(exported, overwrite: true), 1);
  });

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
    'SyncBundleKeyService does not create a key when reading existing only',
    () async {
      final secureStore = MemorySecureKeyValueStore();
      final service = SyncBundleKeyService(
        secureStore: secureStore,
        keyFactory: () => List<int>.filled(32, 9),
      );

      await expectLater(service.requireExisting(), throwsStateError);
      expect(await secureStore.read('security.sync_bundle_key.v1'), isNull);
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
    'NotesController replaceFromSync preserves local private profile notes',
    () async {
      SharedPreferences.setMockInitialValues({});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'himemo-sync-apply-private-preserve-',
      );
      final secureStore = MemorySecureKeyValueStore();
      final encryptionService = EncryptionService(random: Random(70));
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
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });

      final controller = container.read(notesControllerProvider.notifier);
      await controller.restoreCompleted;
      await controller.upsert(
        NoteEntry(
          id: 'local-everyday',
          vaultId: 'everyday',
          title: 'Local everyday',
          body: 'Should be replaced',
          createdAt: DateTime(2026, 4, 12, 8, 0),
        ),
      );
      await controller.upsert(
        NoteEntry(
          id: 'local-private',
          vaultId: legacyPrivateVaultId,
          title: 'Local private',
          body: 'Must survive a smaller remote snapshot',
          createdAt: DateTime(2026, 4, 12, 8, 30),
        ),
      );

      await controller.replaceFromSync([
        NoteEntry(
          id: 'remote-everyday',
          vaultId: 'everyday',
          title: 'Remote everyday',
          body: 'From remote bundle',
          createdAt: DateTime(2026, 4, 12, 18, 0),
        ),
      ]);

      final ids = container
          .read(notesControllerProvider)
          .map((note) => note.id)
          .toSet();
      expect(ids, contains('remote-everyday'));
      expect(ids, contains('local-private'));
      expect(ids, isNot(contains('local-everyday')));
    },
  );

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
      var pendingChanges = await noteDatabase.loadPendingChanges();
      expect(pendingChanges, hasLength(1));
      expect(pendingChanges.single.noteId, 'remote-a');
      expect(pendingChanges.single.action, PendingNoteChangeAction.upsert);

      await controller.markCurrentStateSynced();
      final resolved = container
          .read(notesControllerProvider)
          .singleWhere((note) => note.id == 'remote-a');
      expect(resolved.syncState, NoteSyncState.synced);
      pendingChanges = await noteDatabase.loadPendingChanges();
      expect(pendingChanges, isEmpty);

      await controller.mergeFromSync([
        PreparedSyncNote(
          action: PendingNoteChangeAction.upsert,
          note: NoteEntry(
            id: 'remote-a',
            vaultId: 'everyday',
            title: 'Older remote edit',
            body: 'Remote is behind this device',
            createdAt: DateTime(2026, 4, 13, 9, 0),
            updatedAt: DateTime(2026, 4, 13, 8, 30),
            revision: 2,
            contentHash: 'remote-a-v2-old',
          ),
        ),
      ]);

      final queuedForConvergence = container
          .read(notesControllerProvider)
          .singleWhere((note) => note.id == 'remote-a');
      expect(queuedForConvergence.title, 'Local edit');
      expect(queuedForConvergence.syncState, NoteSyncState.pendingUpload);
      pendingChanges = await noteDatabase.loadPendingChanges();
      expect(pendingChanges, hasLength(1));
      expect(pendingChanges.single.noteId, 'remote-a');
      expect(pendingChanges.single.action, PendingNoteChangeAction.upsert);

      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    },
  );

  test(
    'NotesController applies remote deletes as trash without losing local content',
    () async {
      SharedPreferences.setMockInitialValues({});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'himemo-sync-delete-merge-',
      );
      final secureStore = MemorySecureKeyValueStore();
      final encryptionService = EncryptionService(random: Random(66));
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
      final createdAt = DateTime(2026, 5, 19, 14);
      await controller.upsert(
        NoteEntry(
          id: 'delete-remote',
          vaultId: 'everyday',
          title: 'Keep this title',
          body: 'Keep this body in trash.',
          createdAt: createdAt,
          updatedAt: createdAt,
          revision: 2,
          attachments: const [
            NoteAttachment(
              type: AttachmentType.photo,
              label: 'kept.jpg',
              filePath: 'secure-attachment://kept',
            ),
          ],
        ),
      );
      await controller.markCurrentStateSynced();
      final deletedAt = createdAt.add(const Duration(minutes: 20));

      await controller.mergeFromSync([
        PreparedSyncNote(
          action: PendingNoteChangeAction.delete,
          note: NoteEntry(
            id: 'delete-remote',
            vaultId: 'everyday',
            title: '',
            body: '',
            createdAt: createdAt,
            updatedAt: deletedAt,
            deletedAt: deletedAt,
            revision: 3,
            contentHash: 'remote-delete-hash',
          ),
        ),
      ]);

      final trashed = container
          .read(notesControllerProvider)
          .singleWhere((note) => note.id == 'delete-remote');
      expect(trashed.deletedAt, deletedAt);
      expect(trashed.title, 'Keep this title');
      expect(trashed.body, 'Keep this body in trash.');
      expect(trashed.attachments.single.label, 'kept.jpg');
      expect(trashed.syncState, NoteSyncState.synced);
      expect(trashed.contentHash, 'remote-delete-hash');

      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    },
  );

  test(
    'NotesController resolves delete sync conflicts conservatively',
    () async {
      SharedPreferences.setMockInitialValues({});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'himemo-sync-delete-conflict-',
      );
      final secureStore = MemorySecureKeyValueStore();
      final encryptionService = EncryptionService(random: Random(67));
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
      final createdAt = DateTime(2026, 5, 19, 15);
      final deletedAt = createdAt.add(const Duration(minutes: 30));
      await controller.upsert(
        NoteEntry(
          id: 'delete-conflict',
          vaultId: 'everyday',
          title: 'Base',
          body: 'Base body',
          createdAt: createdAt,
          updatedAt: createdAt,
          revision: 1,
        ),
      );
      await controller.markCurrentStateSynced();
      await controller.upsert(
        NoteEntry(
          id: 'delete-conflict',
          vaultId: 'everyday',
          title: 'Local edit',
          body: 'Unsynced local edit',
          createdAt: createdAt,
          updatedAt: createdAt.add(const Duration(minutes: 10)),
          revision: 1,
        ),
      );

      await controller.mergeFromSync([
        PreparedSyncNote(
          action: PendingNoteChangeAction.delete,
          note: NoteEntry(
            id: 'delete-conflict',
            vaultId: 'everyday',
            title: '',
            body: '',
            createdAt: createdAt,
            updatedAt: deletedAt,
            deletedAt: deletedAt,
            revision: 2,
            contentHash: 'remote-delete-conflict',
          ),
        ),
      ]);

      var note = container
          .read(notesControllerProvider)
          .singleWhere((entry) => entry.id == 'delete-conflict');
      expect(note.title, 'Local edit');
      expect(note.deletedAt, isNull);
      expect(note.syncState, NoteSyncState.conflict);

      await controller.delete('delete-conflict');
      await controller.mergeFromSync([
        PreparedSyncNote(
          action: PendingNoteChangeAction.delete,
          note: NoteEntry(
            id: 'delete-conflict',
            vaultId: 'everyday',
            title: '',
            body: '',
            createdAt: createdAt,
            updatedAt: deletedAt.add(const Duration(minutes: 10)),
            deletedAt: deletedAt.add(const Duration(minutes: 10)),
            revision: 3,
            contentHash: 'remote-delete-agreed',
          ),
        ),
      ]);

      note = container
          .read(notesControllerProvider)
          .singleWhere((entry) => entry.id == 'delete-conflict');
      expect(note.deletedAt, isNotNull);
      expect(note.syncState, NoteSyncState.synced);
      expect(note.contentHash, 'remote-delete-agreed');

      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    },
  );

  test(
    'NotesController keeps notes created while a sync is finishing',
    () async {
      SharedPreferences.setMockInitialValues({});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'himemo-sync-create-during-upload-',
      );
      final secureStore = MemorySecureKeyValueStore();
      final encryptionService = EncryptionService(random: Random(69));
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
      final createdAt = DateTime(2026, 5, 24, 23, 49);
      await controller.upsert(
        NoteEntry(
          id: 'already-uploading',
          vaultId: 'everyday',
          title: 'Already uploading',
          body: 'This change was in the snapshot.',
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      );
      final uploadingHash = container
          .read(notesControllerProvider)
          .singleWhere((entry) => entry.id == 'already-uploading')
          .contentHash;

      await controller.upsert(
        NoteEntry(
          id: 'created-during-sync',
          vaultId: 'everyday',
          title: 'Created during sync',
          body: 'This note must stay local after the current upload finishes.',
          createdAt: createdAt.add(const Duration(seconds: 5)),
          updatedAt: createdAt.add(const Duration(seconds: 5)),
        ),
      );

      await controller.markSnapshotChangesSynced({
        'already-uploading': uploadingHash,
      });

      final afterUpload = container.read(notesControllerProvider);
      expect(
        afterUpload
            .singleWhere((entry) => entry.id == 'already-uploading')
            .syncState,
        NoteSyncState.synced,
      );
      final createdDuringSync = afterUpload.singleWhere(
        (entry) => entry.id == 'created-during-sync',
      );
      expect(createdDuringSync.deletedAt, isNull);
      expect(createdDuringSync.syncState, NoteSyncState.pendingUpload);

      await controller.mergeFromSync([
        PreparedSyncNote(
          action: PendingNoteChangeAction.delete,
          note: NoteEntry(
            id: 'created-during-sync',
            vaultId: 'everyday',
            title: '',
            body: '',
            createdAt: createdAt,
            updatedAt: createdAt.add(const Duration(minutes: 1)),
            deletedAt: createdAt.add(const Duration(minutes: 1)),
            revision: 2,
            contentHash: 'remote-delete-for-created-during-sync',
          ),
        ),
      ]);

      final afterRemoteDelete = container
          .read(notesControllerProvider)
          .singleWhere((entry) => entry.id == 'created-during-sync');
      expect(afterRemoteDelete.title, 'Created during sync');
      expect(afterRemoteDelete.body, contains('must stay local'));
      expect(afterRemoteDelete.deletedAt, isNull);
      expect(afterRemoteDelete.syncState, NoteSyncState.conflict);
      expect(container.read(visibleNotesProvider), contains(afterRemoteDelete));

      final pendingChanges = await noteDatabase.loadPendingChanges();
      expect(
        pendingChanges.where(
          (change) => change.noteId == 'created-during-sync',
        ),
        hasLength(1),
      );

      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    },
  );

  test(
    'NotesController does not resurrect locally trashed notes from remote upserts',
    () async {
      SharedPreferences.setMockInitialValues({});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'himemo-sync-trash-upsert-conflict-',
      );
      final secureStore = MemorySecureKeyValueStore();
      final encryptionService = EncryptionService(random: Random(68));
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
      final createdAt = DateTime(2026, 5, 19, 16);
      await controller.upsert(
        NoteEntry(
          id: 'trash-upsert',
          vaultId: 'everyday',
          title: 'Deleted locally',
          body: 'Keep this note in trash.',
          createdAt: createdAt,
          updatedAt: createdAt,
          revision: 3,
        ),
      );
      await controller.markCurrentStateSynced();
      await controller.delete('trash-upsert');
      await controller.markCurrentStateSynced();

      await controller.mergeFromSync([
        PreparedSyncNote(
          action: PendingNoteChangeAction.upsert,
          note: NoteEntry(
            id: 'trash-upsert',
            vaultId: 'everyday',
            title: 'Remote edit',
            body: 'The remote side still has an active note.',
            createdAt: createdAt,
            updatedAt: createdAt.add(const Duration(hours: 1)),
            revision: 5,
            contentHash: 'remote-active-hash',
          ),
        ),
      ]);

      final note = container
          .read(notesControllerProvider)
          .singleWhere((entry) => entry.id == 'trash-upsert');
      expect(note.deletedAt, isNotNull);
      expect(note.title, 'Deleted locally');
      expect(note.body, 'Keep this note in trash.');
      expect(note.syncState, NoteSyncState.conflict);
      expect(
        container
            .read(visibleNotesProvider)
            .any((entry) => entry.id == 'trash-upsert'),
        isFalse,
      );

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
      modifiedAt: DateTime.parse('2026-04-12T19:00:00+09:00'),
      deviceId: 'remote-device',
    );

    await store.recordRemoteStatus(remote);
    await store.recordApply(remote);
    final restored = await store.read();

    expect(restored.lastRemoteFileId, 'file-1');
    expect(restored.lastRemoteDeviceId, 'remote-device');
    expect(restored.lastRemoteModifiedAt, DateTime.utc(2026, 4, 12, 10));
    expect(restored.lastAppliedAt, isNotNull);
  });

  test('SyncBundleStateStore normalizes persisted timestamps to UTC', () async {
    SharedPreferences.setMockInitialValues({
      'sync.bundle_state.v1': jsonEncode({
        'lastRemoteFileId': 'file-utc',
        'lastRemoteModifiedAt': '2026-05-09T22:00:00+09:00',
        'lastRemoteDeviceId': 'remote-device',
        'lastUploadedAt': '2026-05-09T13:05:00Z',
        'lastAppliedAt': '2026-05-09T22:10:00+09:00',
      }),
    });
    final store = SyncBundleStateStore(
      sharedPreferencesProvider: SharedPreferences.getInstance,
    );

    final restored = await store.read();

    expect(restored.lastRemoteModifiedAt, DateTime.utc(2026, 5, 9, 13));
    expect(restored.lastUploadedAt, DateTime.utc(2026, 5, 9, 13, 5));
    expect(restored.lastAppliedAt, DateTime.utc(2026, 5, 9, 13, 10));
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
        isTrue,
      );
    },
  );

  test(
    'remote bundle apply check is not suppressed by status refresh alone',
    () {
      final observedOnly = SyncBundleState(
        lastRemoteFileId: 'remote-observed',
        lastRemoteModifiedAt: DateTime.utc(2026, 5, 9, 10),
      );

      expect(
        remoteBundleNeedsApplyForSync(
          RemoteSyncBundleStatus(
            fileId: 'remote-observed',
            fileName: 'latest_sync_bundle.enc',
            modifiedAt: DateTime.utc(2026, 5, 9, 10),
          ),
          observedOnly,
        ),
        isTrue,
      );
    },
  );

  test(
    'sync conflict assessment compares equivalent time zones as instants',
    () {
      final assessment = assessSyncConflict(
        googleDriveSelected: true,
        queue: const SyncQueueSummary(totalChanges: 1, upserts: 1, deletes: 0),
        remoteStatus: RemoteSyncBundleStatus(
          fileId: 'remote-1',
          fileName: 'himemo_sync_bundle.enc',
          modifiedAt: DateTime.parse('2026-05-09T22:00:00+09:00'),
          deviceId: 'other-device',
        ),
        bundleState: SyncBundleState(
          lastRemoteFileId: 'remote-0',
          lastRemoteModifiedAt: DateTime.utc(2026, 5, 9, 12, 30),
          lastRemoteDeviceId: 'device-a',
          lastUploadedAt: DateTime.utc(2026, 5, 9, 13),
        ),
      );

      expect(assessment.hasConflict, isFalse);
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
      expect(assessment.message, 'sync.error.conflict_pending_remote_newer');
    },
  );

  test('assessSyncConflict allows local queue newer than remote bundle', () {
    final assessment = assessSyncConflict(
      googleDriveSelected: true,
      queue: SyncQueueSummary(
        totalChanges: 1,
        upserts: 1,
        deletes: 0,
        lastQueuedAt: DateTime.utc(2026, 4, 12, 20, 5),
      ),
      remoteStatus: RemoteSyncBundleStatus(
        fileId: 'remote-1',
        fileName: 'himemo_sync_bundle.enc',
        modifiedAt: DateTime.utc(2026, 4, 12, 20),
        deviceId: 'device-a',
      ),
      bundleState: SyncBundleState(
        lastRemoteFileId: 'remote-0',
        lastRemoteModifiedAt: DateTime.utc(2026, 4, 12, 19),
        lastRemoteDeviceId: 'device-a',
        lastUploadedAt: DateTime.utc(2026, 4, 12, 19, 15),
      ),
    );

    expect(assessment.hasConflict, isFalse);
    expect(assessment.message, isNull);
  });

  test('assessSyncConflict ignores stale remote bundle', () {
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

  test('assessSyncConflict does not trust refreshed device id alone', () {
    final assessment = assessSyncConflict(
      googleDriveSelected: true,
      queue: const SyncQueueSummary(totalChanges: 1, upserts: 1, deletes: 0),
      remoteStatus: RemoteSyncBundleStatus(
        fileId: 'remote-2',
        fileName: 'himemo_sync_bundle.enc',
        modifiedAt: DateTime(2026, 4, 12, 20, 0),
        deviceId: 'device-a',
      ),
      bundleState: SyncBundleState(
        lastRemoteFileId: 'remote-2',
        lastRemoteModifiedAt: DateTime(2026, 4, 12, 20, 0),
        lastRemoteDeviceId: 'device-a',
        lastAppliedAt: DateTime(2026, 4, 12, 19, 0),
      ),
    );

    expect(assessment.hasConflict, isTrue);
    expect(assessment.message, 'sync.error.conflict_pending_remote_newer');
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

  test('buildSyncBundlePreview reports private vault coverage', () {
    final preview = buildSyncBundlePreview(
      decodedBundle: {
        'notes': [
          {
            'action': 'upsert',
            'note': NoteEntry(
              id: 'private-note',
              vaultId: 'private_profile:profile-a',
              title: 'Private title',
              body: 'Private body',
              createdAt: DateTime(2026, 4, 12, 11, 0),
            ).toJson(),
          },
        ],
        'encryptedPrivateNotes': [
          {
            'action': 'upsert',
            'note': {
              'id': 'locked-private-note',
              'vaultId': 'private_profile:profile-b',
              'createdAt': '2026-04-12T11:00:00.000',
              'isPinned': false,
              'revision': 1,
              'syncState': 'synced',
              'encryptedPayload': 'payload',
            },
            'attachments': [],
          },
        ],
      },
      currentNotes: const [],
    );

    expect(preview.privateVaultNoteCount, 2);
    expect(preview.privateVaultIds, {
      'private_profile:profile-a',
      'private_profile:profile-b',
    });
    expect(preview.addedTitles, ['Private title']);
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

  @override
  Future<void> protectAttachmentForVault(
    String storedReference, {
    required AttachmentType type,
    required String vaultId,
  }) async {}
}

class _ReadTrackingEncryptedAttachmentStore extends EncryptedAttachmentStore {
  _ReadTrackingEncryptedAttachmentStore({
    required super.encryptionService,
    required super.masterKeyService,
    required super.directoryProvider,
    required super.sharedPreferencesProvider,
  });

  int readCount = 0;

  @override
  Future<List<int>?> readAttachment(
    String storedReference, {
    required AttachmentType type,
  }) {
    readCount += 1;
    return super.readAttachment(storedReference, type: type);
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
