import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/home/presentation/home_providers.dart';
import 'package:himemo/features/security/data/encrypted_attachment_store.dart';
import 'package:himemo/features/security/data/encrypted_note_database.dart';
import 'package:himemo/features/security/data/encrypted_note_store.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/master_key_service.dart';
import 'package:himemo/features/security/data/profile_data_key_service.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'normal profile sessions expose one profile and switch clears the old key',
    () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      final profiles = await h.seedProfiles();

      final unlock = h.container.read(
        privateProfileUnlockControllerProvider.notifier,
      );
      expect(
        (await unlock.unlockWithPassword('alpha-password'))?.vaultId,
        profiles.alpha.vaultId,
      );
      expect(h.keys.isProfileUnlocked(profiles.alpha.vaultId), isTrue);
      expect(
        h.container.read(visibleNotesProvider).map((note) => note.id),
        contains('alpha-note'),
      );
      expect(
        h.container.read(visibleNotesProvider).map((note) => note.id),
        isNot(contains('beta-note')),
      );

      expect(
        (await unlock.unlockWithPassword('beta-password'))?.vaultId,
        profiles.beta.vaultId,
      );
      expect(h.keys.isProfileUnlocked(profiles.alpha.vaultId), isFalse);
      expect(h.keys.isProfileUnlocked(profiles.beta.vaultId), isTrue);
      expect(
        h.container.read(visibleNotesProvider).map((note) => note.id),
        contains('beta-note'),
      );
      expect(
        h.container.read(visibleNotesProvider).map((note) => note.id),
        isNot(contains('alpha-note')),
      );
    },
  );

  test(
    'admin unlock restores both notes and attachments, and lock redacts them',
    () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      final profiles = await h.seedProfiles(withAttachments: true);
      h.keys.lockAllPrivateProfiles();
      await h.container
          .read(notesControllerProvider.notifier)
          .reloadFromStorage();

      final missing = await h.container
          .read(adminModeSessionControllerProvider.notifier)
          .unlock();
      expect(missing, isEmpty);
      expect(h.container.read(adminModeSessionControllerProvider), isTrue);
      expect(h.keys.isProfileUnlocked(profiles.alpha.vaultId), isTrue);
      expect(h.keys.isProfileUnlocked(profiles.beta.vaultId), isTrue);
      expect(
        h.container.read(visibleNotesProvider).map((note) => note.id),
        containsAll(<String>['alpha-note', 'beta-note']),
      );
      final restored = h.container.read(notesControllerProvider);
      expect(
        restored.singleWhere((note) => note.id == 'alpha-note').body,
        'Alpha secret',
      );
      expect(
        restored.singleWhere((note) => note.id == 'alpha-note').title,
        'Alpha title',
      );
      expect(
        restored.singleWhere((note) => note.id == 'beta-note').body,
        'Beta secret',
      );
      expect(
        restored.singleWhere((note) => note.id == 'beta-note').title,
        'Beta title',
      );
      expect(
        await h.attachments.readAttachment(
          profiles.alphaAttachment!,
          type: AttachmentType.file,
        ),
        [1, 2, 3],
      );
      expect(
        await h.attachments.readAttachment(
          profiles.betaAttachment!,
          type: AttachmentType.file,
        ),
        [4, 5, 6],
      );

      h.container.read(adminModeSessionControllerProvider.notifier).lock();
      expect(h.container.read(adminModeSessionControllerProvider), isFalse);
      expect(h.keys.isProfileUnlocked(profiles.alpha.vaultId), isFalse);
      expect(h.keys.isProfileUnlocked(profiles.beta.vaultId), isFalse);
      final redacted = h.container.read(notesControllerProvider);
      expect(
        redacted
            .where((note) => note.vaultId == profiles.alpha.vaultId)
            .single
            .body,
        isEmpty,
      );
      expect(
        redacted
            .where((note) => note.vaultId == profiles.beta.vaultId)
            .single
            .body,
        isEmpty,
      );
      expect(
        redacted
            .where((note) => note.vaultId == profiles.alpha.vaultId)
            .single
            .title,
        'Locked private note',
      );
      expect(
        () => h.attachments.readAttachment(
          profiles.alphaAttachment!,
          type: AttachmentType.file,
        ),
        throwsStateError,
      );
      expect(
        () => h.attachments.readAttachment(
          profiles.betaAttachment!,
          type: AttachmentType.file,
        ),
        throwsStateError,
      );
    },
  );

  test(
    'normal to admin restores every profile after the active key is cleared',
    () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      final profiles = await h.seedProfiles();
      h.keys.lockAllPrivateProfiles();
      final unlock = h.container.read(
        privateProfileUnlockControllerProvider.notifier,
      );
      expect(
        (await unlock.unlockWithPassword('alpha-password'))?.vaultId,
        profiles.alpha.vaultId,
      );
      expect(h.keys.isProfileUnlocked(profiles.beta.vaultId), isFalse);

      final missing = await h.container
          .read(adminModeSessionControllerProvider.notifier)
          .unlock();
      expect(missing, isEmpty);
      expect(h.keys.isProfileUnlocked(profiles.alpha.vaultId), isTrue);
      expect(h.keys.isProfileUnlocked(profiles.beta.vaultId), isTrue);
      expect(h.container.read(adminModeSessionControllerProvider), isTrue);
    },
  );

  test('admin unlock restores the legacy private vault', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    final legacy = h.container.read(
      privateVaultSecretControllerProvider.notifier,
    );
    await legacy.configure('legacy-password');
    await h.container
        .read(notesControllerProvider.notifier)
        .upsert(
          NoteEntry(
            id: 'legacy-note',
            vaultId: legacyPrivateVaultId,
            title: 'Legacy title',
            body: 'Legacy secret',
            createdAt: DateTime.utc(2026, 9, 21),
          ),
        );
    h.container.read(privateVaultSessionControllerProvider.notifier).lock();
    h.keys.lockAllPrivateProfiles();
    await h.container
        .read(notesControllerProvider.notifier)
        .reloadFromStorage();

    final missing = await h.container
        .read(adminModeSessionControllerProvider.notifier)
        .unlock();
    expect(missing, isEmpty);
    expect(h.keys.isProfileUnlocked(legacyPrivateVaultId), isTrue);
    expect(
      h.container
          .read(notesControllerProvider)
          .singleWhere((note) => note.id == 'legacy-note')
          .body,
      'Legacy secret',
    );
  });

  test(
    'admin to normal keeps only the selected profile, and a mismatch preserves the session',
    () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      final profiles = await h.seedProfiles();
      final admin = h.container.read(
        adminModeSessionControllerProvider.notifier,
      );
      expect(await admin.unlock(), isEmpty);
      expect(h.keys.isProfileUnlocked(profiles.alpha.vaultId), isTrue);
      expect(h.keys.isProfileUnlocked(profiles.beta.vaultId), isTrue);

      final unlock = h.container.read(
        privateProfileUnlockControllerProvider.notifier,
      );
      expect(await unlock.unlockWithPassword('wrong-password'), isNull);
      expect(h.container.read(adminModeSessionControllerProvider), isTrue);
      expect(h.keys.isProfileUnlocked(profiles.alpha.vaultId), isTrue);
      expect(h.keys.isProfileUnlocked(profiles.beta.vaultId), isTrue);

      expect(
        (await unlock.unlockWithPassword('alpha-password'))?.vaultId,
        profiles.alpha.vaultId,
      );
      expect(h.container.read(adminModeSessionControllerProvider), isFalse);
      expect(h.keys.isProfileUnlocked(profiles.alpha.vaultId), isTrue);
      expect(h.keys.isProfileUnlocked(profiles.beta.vaultId), isFalse);
    },
  );

  test(
    'admin unlock reports a missing local wrap and password migration restores it',
    () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      final profiles = await h.seedProfiles();
      await h.secureStore.delete(
        '${h.keys.storagePrefix}.admin.${profiles.alpha.vaultId}',
      );
      h.keys.lockAllPrivateProfiles();

      final admin = h.container.read(
        adminModeSessionControllerProvider.notifier,
      );
      expect(await admin.unlock(), contains(profiles.alpha.vaultId));
      expect(h.keys.isProfileUnlocked(profiles.alpha.vaultId), isFalse);
      expect(
        await admin.unlockProfile(profiles.alpha.vaultId, 'alpha-password'),
        isTrue,
      );
      expect(h.keys.isProfileUnlocked(profiles.alpha.vaultId), isTrue);
      admin.lock();
      expect(await admin.unlock(), isEmpty);
      expect(h.keys.isProfileUnlocked(profiles.alpha.vaultId), isTrue);
    },
  );
}

class _Harness {
  _Harness._({
    required this.container,
    required this.directory,
    required this.database,
    required this.keys,
    required this.secureStore,
    required this.attachments,
  });

  final ProviderContainer container;
  final Directory directory;
  final EncryptedNoteDatabase database;
  final ProfileDataKeyService keys;
  final MemorySecureKeyValueStore secureStore;
  final EncryptedAttachmentStore attachments;

  static Future<_Harness> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'himemo-admin-session-',
    );
    final secureStore = MemorySecureKeyValueStore();
    final encryption = EncryptionService(random: Random(71));
    final master = MasterKeyService(
      secureStore: secureStore,
      keyFactory: encryption.generateKeyBytes,
    );
    final keys = ProfileDataKeyService(
      secureStore: secureStore,
      encryptionService: encryption,
      normalMasterKeyService: master,
    );
    final database = EncryptedNoteDatabase(executor: NativeDatabase.memory());
    final notes = EncryptedNoteStore(
      encryptionService: encryption,
      masterKeyService: master,
      profileDataKeyService: keys,
      database: database,
      directoryProvider: () async => directory,
      sharedPreferencesProvider: SharedPreferences.getInstance,
    );
    final attachments = EncryptedAttachmentStore(
      encryptionService: encryption,
      masterKeyService: master,
      profileDataKeyService: keys,
      directoryProvider: () async => directory,
      sharedPreferencesProvider: SharedPreferences.getInstance,
    );
    final container = ProviderContainer(
      overrides: [
        secureKeyValueStoreProvider.overrideWithValue(secureStore),
        encryptionServiceProvider.overrideWithValue(encryption),
        masterKeyServiceProvider.overrideWithValue(master),
        profileDataKeyServiceProvider.overrideWithValue(keys),
        encryptedNoteDatabaseProvider.overrideWithValue(database),
        encryptedNoteStoreProvider.overrideWithValue(notes),
        encryptedAttachmentStoreProvider.overrideWithValue(attachments),
      ],
    );
    await container.read(notesControllerProvider.notifier).restoreCompleted;
    return _Harness._(
      container: container,
      directory: directory,
      database: database,
      keys: keys,
      secureStore: secureStore,
      attachments: attachments,
    );
  }

  Future<_Profiles> seedProfiles({bool withAttachments = false}) async {
    final profilesController = container.read(
      privateMemoProfilesControllerProvider.notifier,
    );
    await profilesController.addProfile(
      name: 'Alpha',
      password: 'alpha-password',
    );
    await profilesController.addProfile(
      name: 'Beta',
      password: 'beta-password',
    );
    final profiles = container.read(privateMemoProfilesProvider);
    final alpha = profiles.singleWhere((p) => p.name == 'Alpha');
    final beta = profiles.singleWhere((p) => p.name == 'Beta');
    final alphaAttachment = withAttachments
        ? await _attachment(alpha.vaultId, [1, 2, 3], 'alpha.bin')
        : null;
    final betaAttachment = withAttachments
        ? await _attachment(beta.vaultId, [4, 5, 6], 'beta.bin')
        : null;
    await container
        .read(notesControllerProvider.notifier)
        .upsert(
          NoteEntry(
            id: 'alpha-note',
            vaultId: alpha.vaultId,
            title: 'Alpha title',
            body: 'Alpha secret',
            createdAt: DateTime.utc(2026, 9, 21),
            attachments: [
              if (alphaAttachment != null)
                NoteAttachment(
                  type: AttachmentType.file,
                  label: 'alpha.bin',
                  filePath: alphaAttachment,
                ),
            ],
          ),
        );
    await container
        .read(notesControllerProvider.notifier)
        .upsert(
          NoteEntry(
            id: 'beta-note',
            vaultId: beta.vaultId,
            title: 'Beta title',
            body: 'Beta secret',
            createdAt: DateTime.utc(2026, 9, 21),
            attachments: [
              if (betaAttachment != null)
                NoteAttachment(
                  type: AttachmentType.file,
                  label: 'beta.bin',
                  filePath: betaAttachment,
                ),
            ],
          ),
        );
    return _Profiles(
      alpha: alpha,
      beta: beta,
      alphaAttachment: alphaAttachment,
      betaAttachment: betaAttachment,
    );
  }

  Future<String?> _attachment(
    String vaultId,
    List<int> bytes,
    String name,
  ) async {
    final payload = await attachments.encryptAttachmentBytes(
      bytes: bytes,
      type: AttachmentType.file,
      vaultId: vaultId,
    );
    return attachments.storeEncryptedPayload(
      encodedPayload: payload,
      type: AttachmentType.file,
      fileNameHint: name,
      vaultId: vaultId,
    );
  }

  Future<void> dispose() async {
    container.dispose();
    await database.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

class _Profiles {
  _Profiles({
    required this.alpha,
    required this.beta,
    this.alphaAttachment,
    this.betaAttachment,
  });
  final PrivateMemoProfile alpha;
  final PrivateMemoProfile beta;
  final String? alphaAttachment;
  final String? betaAttachment;
}
