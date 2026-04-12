import 'dart:convert';
import 'dart:io';
import 'dart:math';

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
import 'package:himemo/features/security/data/private_vault_secret_store.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:image_picker/image_picker.dart';
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
      expect(records.single.encryptedPayload.contains('Encrypted body'), isFalse);
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
        ),
      ];

      await noteStore.save(notes);
      final restored = await noteStore.load(fallbackNotes: const []);

      expect(restored, notes);
      final records = await database.loadAll();
      expect(records, hasLength(1));
      final rawPayload = records.single.encryptedPayload;
      expect(rawPayload.contains('Vault plan'), isFalse);
      expect(rawPayload.contains('Only encrypted payload should be stored.'), isFalse);
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

    test('stores and verifies private vault secret in secure storage', () async {
      expect(await secretStore.hasSecret(), isFalse);

      await secretStore.configure('top-secret');

      expect(await secretStore.hasSecret(), isTrue);
      expect(await secretStore.verify('top-secret'), isTrue);
      expect(await secretStore.verify('not-it'), isFalse);
      final stored = await secureStore.read('security.private_vault.verifier.v1');
      expect(stored, isNotNull);
      expect(stored!.contains('top-secret'), isFalse);
    });

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
    late EncryptedAttachmentStore attachmentStore;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      tempDirectory = await Directory.systemTemp.createTemp(
        'himemo-secure-attachments-',
      );
      secureStore = MemorySecureKeyValueStore();
      encryptionService = EncryptionService(random: Random(13));
      attachmentStore = EncryptedAttachmentStore(
        encryptionService: encryptionService,
        masterKeyService: MasterKeyService(
          secureStore: secureStore,
          keyFactory: encryptionService.generateKeyBytes,
        ),
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
      final source = File('${tempDirectory.path}${Platform.pathSeparator}raw.jpg');
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
    final original = container.read(notesControllerProvider).single;
    await controller.upsert(
      original.copyWith(attachments: const <NoteAttachment>[]),
    );

    expect(fakeAttachmentStore.deletedReferences, ['secure-attachment://old']);
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

    final saved = container.read(notesControllerProvider).singleWhere(
      (note) => note.id == 'sync-1',
    );
    expect(saved.deviceId, isNotNull);
    expect(saved.contentHash, isNotNull);
    expect(saved.syncState, NoteSyncState.pendingUpload);
    expect(saved.deletedAt, isNull);

    await controller.delete('sync-1');
    final deleted = container.read(notesControllerProvider).singleWhere(
      (note) => note.id == 'sync-1',
    );
    expect(deleted.deletedAt, isNotNull);
    expect(deleted.syncState, NoteSyncState.pendingDelete);
    expect(container.read(visibleNotesProvider).any((n) => n.id == 'sync-1'), isFalse);
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
  List<VaultBucket> get vaults => const <VaultBucket>[];
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
    VaultBucket(
      id: 'everyday',
      name: 'Daily Notes',
      description: 'Test vault',
    ),
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
