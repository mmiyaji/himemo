import 'dart:io';
import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himemo/app/app.dart';
import 'package:himemo/app/app_flavor.dart';
import 'package:himemo/features/home/data/home_repository.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/home/domain/note_tags.dart';
import 'package:himemo/features/home/presentation/home_page.dart';
import 'package:himemo/features/home/presentation/home_providers.dart';
import 'package:himemo/features/security/data/encrypted_note_database.dart';
import 'package:himemo/features/security/data/encrypted_note_store.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/master_key_service.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:himemo/l10n/app_strings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('app strings fall back to English for unsupported locales', () {
    final strings = AppStrings(const Locale('fr'));

    expect(strings.createDemoNotes, 'Create demo notes');
    expect(strings.deleteDemoNotesBody(3), contains('3 demo notes'));
    expect(strings.noteDayLabel(DateTime(2026, 5, 3)), 'May 3, 2026 (Sun)');
  });

  test('providers expose private profiles only after unlock', () async {
    SharedPreferences.setMockInitialValues({});
    final secureStore = MemorySecureKeyValueStore();
    final encryptionService = EncryptionService(random: Random(3));
    final masterKeyService = MasterKeyService(
      secureStore: secureStore,
      keyFactory: encryptionService.generateKeyBytes,
    );
    final database = EncryptedNoteDatabase(executor: NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        secureKeyValueStoreProvider.overrideWithValue(secureStore),
        encryptionServiceProvider.overrideWithValue(encryptionService),
        masterKeyServiceProvider.overrideWithValue(masterKeyService),
        encryptedNoteDatabaseProvider.overrideWithValue(database),
        encryptedNoteStoreProvider.overrideWithValue(
          EncryptedNoteStore(
            encryptionService: encryptionService,
            masterKeyService: masterKeyService,
            database: database,
            directoryProvider: () async => Directory.systemTemp,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(database.close);

    expect(container.read(identitiesProvider).length, 3);
    expect(container.read(visibleVaultsProvider).length, 1);

    final addError = await container
        .read(privateMemoProfilesControllerProvider.notifier)
        .addProfile(name: 'Cover profile', password: 'cover-pass-123');
    expect(addError, isNull);
    expect(container.read(privateMemoProfilesProvider).length, 1);
    expect(container.read(visibleVaultsProvider).length, 1);

    final unlocked = await container
        .read(privateProfileUnlockControllerProvider.notifier)
        .unlockWithPassword('cover-pass-123');
    expect(unlocked, isNotNull);

    expect(container.read(visibleVaultsProvider).length, 2);
    expect(
      container
          .read(visibleVaultsProvider)
          .any((vault) => vault.id == unlocked!.vaultId),
      isTrue,
    );
  });

  test('private profile notes remain visible immediately after save', () async {
    SharedPreferences.setMockInitialValues({});
    final secureStore = MemorySecureKeyValueStore();
    final encryptionService = EncryptionService(random: Random(13));
    final masterKeyService = MasterKeyService(
      secureStore: secureStore,
      keyFactory: encryptionService.generateKeyBytes,
    );
    final database = EncryptedNoteDatabase(executor: NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        secureKeyValueStoreProvider.overrideWithValue(secureStore),
        encryptionServiceProvider.overrideWithValue(encryptionService),
        masterKeyServiceProvider.overrideWithValue(masterKeyService),
        encryptedNoteDatabaseProvider.overrideWithValue(database),
        encryptedNoteStoreProvider.overrideWithValue(
          EncryptedNoteStore(
            encryptionService: encryptionService,
            masterKeyService: masterKeyService,
            database: database,
            directoryProvider: () async => Directory.systemTemp,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(database.close);

    final addError = await container
        .read(privateMemoProfilesControllerProvider.notifier)
        .addProfile(name: 'Private journal', password: 'journal-pass-123');
    expect(addError, isNull);

    final unlocked = await container
        .read(privateProfileUnlockControllerProvider.notifier)
        .unlockWithPassword('journal-pass-123');
    expect(unlocked, isNotNull);

    await container
        .read(notesControllerProvider.notifier)
        .upsert(
          NoteEntry(
            id: 'private-after-save',
            vaultId: unlocked!.vaultId,
            title: 'Private saved note',
            body: 'This should remain visible.',
            createdAt: DateTime(2026, 4, 20, 12, 0),
          ),
        );

    expect(
      container.read(visibleNotesProvider).map((note) => note.id),
      contains('private-after-save'),
    );
    expect(
      container.read(notesForVaultProvider(unlocked.vaultId)).single.id,
      'private-after-save',
    );
  });

  test('seeded demo notes are dated within a week of first launch', () {
    final launchDate = DateTime(2026, 4, 29, 15, 30);
    final notes = SeededHomeRepository(seedBaseDate: launchDate).seededNotes;
    final launchDay = DateTime(2026, 4, 29);
    final earliestDemoDay = launchDay.subtract(const Duration(days: 7));

    expect(notes, isNotEmpty);
    for (final note in notes) {
      final noteDay = DateTime(
        note.createdAt.year,
        note.createdAt.month,
        note.createdAt.day,
      );
      expect(noteDay.isBefore(earliestDemoDay), isFalse);
      expect(noteDay.isAfter(launchDay), isFalse);
    }
    expect(
      notes.any(
        (note) =>
            note.createdAt.year == launchDay.year &&
            note.createdAt.month == launchDay.month &&
            note.createdAt.day == launchDay.day,
      ),
      isTrue,
    );
  });

  test(
    'demo notes are only created on request and are not restored automatically after deletion',
    () async {
      SharedPreferences.setMockInitialValues({});
      final secureStore = MemorySecureKeyValueStore();
      final encryptionService = EncryptionService(random: Random(14));
      final masterKeyService = MasterKeyService(
        secureStore: secureStore,
        keyFactory: encryptionService.generateKeyBytes,
      );
      final database = EncryptedNoteDatabase(executor: NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [
          secureKeyValueStoreProvider.overrideWithValue(secureStore),
          encryptionServiceProvider.overrideWithValue(encryptionService),
          masterKeyServiceProvider.overrideWithValue(masterKeyService),
          encryptedNoteDatabaseProvider.overrideWithValue(database),
          encryptedNoteStoreProvider.overrideWithValue(
            EncryptedNoteStore(
              encryptionService: encryptionService,
              masterKeyService: masterKeyService,
              database: database,
              directoryProvider: () async => Directory.systemTemp,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(database.close);

      await container.read(notesControllerProvider.notifier).restoreCompleted;
      expect(container.read(notesControllerProvider), isEmpty);

      final createdCount = await container
          .read(notesControllerProvider.notifier)
          .createDemoNotes();
      final initialSeedCount = container
          .read(notesControllerProvider)
          .where((note) => note.id.startsWith('seed-'))
          .length;
      expect(initialSeedCount, greaterThan(0));
      expect(createdCount, initialSeedCount);

      final deletedCount = await container
          .read(notesControllerProvider.notifier)
          .deleteDemoNotes();
      expect(deletedCount, initialSeedCount);
      expect(
        container
            .read(notesControllerProvider)
            .where((note) => note.id.startsWith('seed-')),
        isEmpty,
      );

      final secondContainer = ProviderContainer(
        overrides: [
          secureKeyValueStoreProvider.overrideWithValue(secureStore),
          encryptionServiceProvider.overrideWithValue(encryptionService),
          masterKeyServiceProvider.overrideWithValue(masterKeyService),
          encryptedNoteDatabaseProvider.overrideWithValue(database),
          encryptedNoteStoreProvider.overrideWithValue(
            EncryptedNoteStore(
              encryptionService: encryptionService,
              masterKeyService: masterKeyService,
              database: database,
              directoryProvider: () async => Directory.systemTemp,
            ),
          ),
        ],
      );
      addTearDown(secondContainer.dispose);
      await secondContainer
          .read(notesControllerProvider.notifier)
          .restoreCompleted;
      expect(
        secondContainer
            .read(notesControllerProvider)
            .where((note) => note.id.startsWith('seed-')),
        isEmpty,
      );
    },
  );

  test('privacy screen activates for legacy private vault session', () {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(privacyScreenActiveProvider), isFalse);
    container.read(privateVaultSessionControllerProvider.notifier).unlock();
    expect(container.read(privacyScreenActiveProvider), isTrue);
    container.read(privateVaultSessionControllerProvider.notifier).lock();
    expect(container.read(privacyScreenActiveProvider), isFalse);
  });

  test('app lock policy providers expose secure defaults', () {
    SharedPreferences.setMockInitialValues({});
    final secureStore = MemorySecureKeyValueStore();
    final encryptionService = EncryptionService(random: Random(4));
    final masterKeyService = MasterKeyService(
      secureStore: secureStore,
      keyFactory: encryptionService.generateKeyBytes,
    );
    final database = EncryptedNoteDatabase(executor: NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        secureKeyValueStoreProvider.overrideWithValue(secureStore),
        encryptionServiceProvider.overrideWithValue(encryptionService),
        masterKeyServiceProvider.overrideWithValue(masterKeyService),
        encryptedNoteDatabaseProvider.overrideWithValue(database),
        encryptedNoteStoreProvider.overrideWithValue(
          EncryptedNoteStore(
            encryptionService: encryptionService,
            masterKeyService: masterKeyService,
            database: database,
            directoryProvider: () async => Directory.systemTemp,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(database.close);

    expect(
      container.read(appLockRelockDelayControllerProvider),
      AppLockRelockDelay.immediate,
    );
    expect(container.read(privateVaultLockOnAppLockControllerProvider), isTrue);
  });

  testWidgets('app renders HiMemo shell', (tester) async {
    SharedPreferences.setMockInitialValues({'app.onboarding_completed': true});
    final secureStore = MemorySecureKeyValueStore();
    final encryptionService = EncryptionService(random: Random(5));
    final masterKeyService = MasterKeyService(
      secureStore: secureStore,
      keyFactory: encryptionService.generateKeyBytes,
    );
    final database = EncryptedNoteDatabase(executor: NativeDatabase.memory());

    configureFlavor(AppFlavor.development);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureKeyValueStoreProvider.overrideWithValue(secureStore),
          encryptionServiceProvider.overrideWithValue(encryptionService),
          masterKeyServiceProvider.overrideWithValue(masterKeyService),
          encryptedNoteDatabaseProvider.overrideWithValue(database),
          encryptedNoteStoreProvider.overrideWithValue(
            EncryptedNoteStore(
              encryptionService: encryptionService,
              masterKeyService: masterKeyService,
              database: database,
              directoryProvider: () async => Directory.systemTemp,
            ),
          ),
        ],
        child: const HiMemoApp(flavor: AppFlavor.development),
      ),
    );
    addTearDown(database.close);
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();

    expect(find.text('HiMemo'), findsOneWidget);
    expect(find.text('Notes'), findsAtLeastNWidgets(1));
    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('mobile tab switch closes open note detail sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({
      'app.onboarding_completed': true,
      'settings.locale': 'english',
    });
    final secureStore = MemorySecureKeyValueStore();
    final encryptionService = EncryptionService(random: Random(16));
    final masterKeyService = MasterKeyService(
      secureStore: secureStore,
      keyFactory: encryptionService.generateKeyBytes,
    );
    final database = EncryptedNoteDatabase(executor: NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        secureKeyValueStoreProvider.overrideWithValue(secureStore),
        encryptionServiceProvider.overrideWithValue(encryptionService),
        masterKeyServiceProvider.overrideWithValue(masterKeyService),
        encryptedNoteDatabaseProvider.overrideWithValue(database),
        encryptedNoteStoreProvider.overrideWithValue(
          EncryptedNoteStore(
            encryptionService: encryptionService,
            masterKeyService: masterKeyService,
            database: database,
            directoryProvider: () async => Directory.systemTemp,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(database.close);

    configureFlavor(AppFlavor.development);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const HiMemoApp(flavor: AppFlavor.development),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump(const Duration(milliseconds: 200));
    await container.read(notesControllerProvider.notifier).createDemoNotes();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(
      find.byKey(const Key('note-tile-seed-2026-04-12-groceries')),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('edit-note-button')), findsOneWidget);

    await tester.tap(find.byKey(AppShell.settingsNavKey));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const Key('edit-note-button')), findsNothing);
    expect(container.read(selectedNoteIdProvider), isNull);
  });

  test('note entry defaults sync metadata safely', () {
    final note = NoteEntry(
      id: 'sample',
      vaultId: 'everyday',
      title: 'Sample',
      body: 'Body',
      createdAt: DateTime(2026, 4, 12, 13, 0),
    );

    expect(note.updatedAt, isNull);
    expect(note.revision, 1);
    expect(note.deletedAt, isNull);
    expect(note.deviceId, isNull);
    expect(note.contentHash, isNull);
    expect(note.syncState, NoteSyncState.localOnly);
    expect(note.blocks, isEmpty);
    expect(note.editorMode, NoteEditorMode.rich);
  });

  test('search filters can narrow notes by tags', () async {
    SharedPreferences.setMockInitialValues({});
    final secureStore = MemorySecureKeyValueStore();
    final encryptionService = EncryptionService(random: Random(6));
    final masterKeyService = MasterKeyService(
      secureStore: secureStore,
      keyFactory: encryptionService.generateKeyBytes,
    );
    final database = EncryptedNoteDatabase(executor: NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        secureKeyValueStoreProvider.overrideWithValue(secureStore),
        encryptionServiceProvider.overrideWithValue(encryptionService),
        masterKeyServiceProvider.overrideWithValue(masterKeyService),
        encryptedNoteDatabaseProvider.overrideWithValue(database),
        encryptedNoteStoreProvider.overrideWithValue(
          EncryptedNoteStore(
            encryptionService: encryptionService,
            masterKeyService: masterKeyService,
            database: database,
            directoryProvider: () async => Directory.systemTemp,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(database.close);

    await container
        .read(notesControllerProvider.notifier)
        .upsert(
          NoteEntry(
            id: 'tag-1',
            vaultId: 'everyday',
            title: 'Project alpha',
            body: 'First body',
            tags: const ['Work', 'Alpha'],
            createdAt: DateTime(2026, 4, 20, 10, 0),
          ),
        );
    await container
        .read(notesControllerProvider.notifier)
        .upsert(
          NoteEntry(
            id: 'tag-2',
            vaultId: 'everyday',
            title: 'Personal errands',
            body: 'Second body',
            tags: const ['Home'],
            createdAt: DateTime(2026, 4, 20, 11, 0),
          ),
        );

    container.read(searchFiltersControllerProvider.notifier).addTag('alpha');

    final visible = container.read(visibleNotesProvider);
    expect(visible.map((note) => note.id), ['tag-1']);
    expect(container.read(visibleTagSuggestionsProvider), contains('Alpha'));
    expect(dedupeNoteTags([' Alpha ', '#alpha', 'HOME']), ['Alpha', 'HOME']);
  });
}
