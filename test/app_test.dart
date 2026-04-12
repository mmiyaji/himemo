import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himemo/app/app.dart';
import 'package:himemo/app/app_flavor.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/home/presentation/home_providers.dart';
import 'package:himemo/features/security/data/encrypted_note_database.dart';
import 'package:himemo/features/security/data/encrypted_note_store.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/master_key_service.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('providers expose separate profiles', () {
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
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(database.close);

    expect(container.read(identitiesProvider).length, 3);
    expect(container.read(visibleVaultsProvider).length, 1);

    container.read(activeIdentityProvider.notifier).switchTo('private');
    expect(container.read(visibleVaultsProvider).length, 1);

    container.read(privateVaultSessionControllerProvider.notifier).unlock();

    expect(container.read(visibleVaultsProvider).length, 2);
    expect(container.read(visibleNotesProvider).length, greaterThanOrEqualTo(4));
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
    SharedPreferences.setMockInitialValues({
      'app.onboarding_completed': true,
    });
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
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
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
}
