import 'dart:io';
import 'dart:math';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himemo/app/app.dart';
import 'package:himemo/app/app_flavor.dart';
import 'package:himemo/app/app_router.dart';
import 'package:himemo/features/home/presentation/home_page.dart';
import 'package:himemo/features/home/presentation/home_providers.dart';
import 'package:himemo/features/security/data/encrypted_note_database.dart';
import 'package:himemo/features/security/data/encrypted_note_store.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/master_key_service.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'tutorial backdrop does not advance and highlighted create button opens editor',
    (tester) async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({
        'app.onboarding_completed': true,
        'app.onboarding_completed_version': 2,
        'settings.locale': 'english',
        'release_notes.last_seen': '1.0.0+1',
      });

      final secureStore = MemorySecureKeyValueStore();
      final encryptionService = EncryptionService(random: Random(81));
      final masterKeyService = MasterKeyService(
        secureStore: secureStore,
        keyFactory: encryptionService.generateKeyBytes,
      );
      final database = EncryptedNoteDatabase(executor: NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [
          unseenReleaseNoteProvider.overrideWith((ref) async => null),
          packageInfoProvider.overrideWith(
            (ref) async => const AppPackageDetails(
              appName: 'HiMemo',
              version: '1.0.0',
              buildNumber: '1',
            ),
          ),
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
      await tester.pumpAndSettle();
      container.read(appSessionUnlockControllerProvider.notifier).unlock();
      await tester.pumpAndSettle();

      container.read(appRouterProvider).go('/notes');
      await tester.pumpAndSettle();
      container.read(appTutorialControllerProvider.notifier).start();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(
        container.read(appTutorialControllerProvider)?.step,
        AppTutorialStep.addNote,
      );
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        tester
            .getRect(find.byKey(AppShell.tutorialCardKey))
            .contains(tester.getRect(find.byKey(AppShell.addNoteKey)).center),
        isFalse,
        reason: 'tutorial card must leave the create control unobstructed',
      );
      await tester.tapAt(const Offset(8, 300));
      await tester.pump();
      expect(
        container.read(appTutorialControllerProvider)?.step,
        AppTutorialStep.addNote,
      );

      expect(find.byKey(AppShell.addNoteKey), findsOneWidget);
      await tester.tap(find.byKey(AppShell.addNoteKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byKey(const Key('save-note-button')), findsOneWidget);
      expect(
        container.read(appTutorialControllerProvider)?.step,
        AppTutorialStep.addNote,
      );
    },
  );
}
