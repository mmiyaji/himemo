import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/app/app.dart';
import 'package:himemo/app/app_flavor.dart';
import 'package:himemo/features/home/presentation/home_page.dart';
import 'package:himemo/features/home/presentation/home_providers.dart';
import 'package:himemo/features/security/data/encrypted_note_database.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('guided tutorial overlay can be completed on Android', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({
      'app.onboarding_completed': true,
      'app.onboarding_completed_version': 2,
      'release_notes.last_seen': '1.0.0+46',
      'settings.locale': 'english',
    });
    final noteDatabase = EncryptedNoteDatabase(
      executor: NativeDatabase.memory(),
    );
    addTearDown(noteDatabase.close);
    final container = ProviderContainer(
      overrides: [
        encryptedNoteDatabaseProvider.overrideWithValue(noteDatabase),
      ],
    );
    addTearDown(container.dispose);

    configureFlavor(AppFlavor.development);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const HiMemoApp(flavor: AppFlavor.development),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();

    container.read(appTutorialControllerProvider.notifier).start();
    await tester.pumpAndSettle();

    expect(find.byKey(AppShell.tutorialCardKey), findsOneWidget);
    expect(find.text('Private profile unlock'), findsOneWidget);
    expect(find.text('Step 1 of 4'), findsOneWidget);

    await tester.tap(find.byKey(AppShell.tutorialNextKey));
    await tester.pumpAndSettle();
    expect(find.text('Create a memo'), findsOneWidget);
    expect(find.text('Step 2 of 4'), findsOneWidget);

    await tester.tap(find.byKey(AppShell.tutorialBackKey));
    await tester.pumpAndSettle();
    expect(find.text('Private profile unlock'), findsOneWidget);
    expect(find.text('Step 1 of 4'), findsOneWidget);

    await tester.tap(find.byKey(AppShell.tutorialNextKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppShell.tutorialNextKey));
    await tester.pumpAndSettle();
    expect(find.text('Sync status'), findsOneWidget);
    expect(find.text('Step 3 of 4'), findsOneWidget);

    await tester.tap(find.byKey(AppShell.tutorialNextKey));
    await tester.pumpAndSettle();
    expect(find.text('Main navigation'), findsOneWidget);
    expect(find.text('Step 4 of 4'), findsOneWidget);

    await tester.tap(find.byKey(AppShell.tutorialNextKey));
    await tester.pumpAndSettle();
    expect(find.byKey(AppShell.tutorialCardKey), findsNothing);
  });
}
