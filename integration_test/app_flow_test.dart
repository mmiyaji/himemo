import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/app/app.dart';
import 'package:himemo/app/app_flavor.dart';
import 'package:himemo/app/app_router.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/home/presentation/home_page.dart';
import 'package:himemo/features/home/presentation/home_providers.dart';
import 'package:himemo/features/security/data/encrypted_note_database.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('core navigation, appearance, and external quick capture work', (
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

    expect(find.byKey(AppShell.addNoteKey), findsOneWidget);

    container.read(appRouterProvider).go('/settings');
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);

    final appearanceHeader = find.textContaining('Appearance');
    await _scrollIntoViewIfNeeded(tester, appearanceHeader);
    await tester.pumpAndSettle();
    await tester.tap(appearanceHeader.first);
    await tester.pumpAndSettle();
    expect(find.text('Language'), findsOneWidget);

    await _scrollIntoViewIfNeeded(
      tester,
      find.byKey(SettingsScreen.darkThemeKey),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SettingsScreen.darkThemeKey));
    await tester.pumpAndSettle();

    final accentColor = find.textContaining('Accent color');
    await _scrollIntoViewIfNeeded(tester, accentColor);
    await tester.tap(accentColor.first);
    await tester.pumpAndSettle();
    await _scrollIntoViewIfNeeded(
      tester,
      find.byKey(SettingsScreen.moegiColorThemeKey),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SettingsScreen.moegiColorThemeKey));
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(app.theme?.colorScheme.primary, const Color(0xFF6F9335));

    final quickCaptureTile = find.widgetWithText(
      SwitchListTile,
      'Allow external quick capture',
    );
    if (quickCaptureTile.evaluate().isEmpty) {
      final appSecurityHeader = find.textContaining('App security');
      if (appSecurityHeader.evaluate().isNotEmpty) {
        await tester.ensureVisible(appSecurityHeader.first);
        await tester.pumpAndSettle();
        await tester.tap(appSecurityHeader.first);
        await tester.pumpAndSettle();
      }
    }
    if (quickCaptureTile.evaluate().isNotEmpty) {
      await _scrollIntoViewIfNeeded(tester, quickCaptureTile);
      await tester.pumpAndSettle();
      await tester.tap(quickCaptureTile);
      await tester.pumpAndSettle();
    } else {
      await container
          .read(widgetQuickCaptureSettingsControllerProvider.notifier)
          .setEnabled(true);
      await tester.pumpAndSettle();
    }

    container.read(appRouterProvider).go('/calendar');
    await tester.pumpAndSettle();
    expect(find.byType(CalendarScreen), findsOneWidget);

    container
        .read(widgetQuickCaptureRequestControllerProvider.notifier)
        .open(
          const QuickCaptureRequest(
            nonce: 'integration-share-1',
            source: QuickCaptureSource.share,
            initialText: 'Shared note from integration test',
          ),
        );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('widget-quick-capture-input')), findsOneWidget);
    expect(
      find.textContaining('Shared note from integration test'),
      findsWidgets,
    );
  });

  testWidgets('language switch and compact list mode behave as expected', (
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

    await container
        .read(notesControllerProvider.notifier)
        .upsert(
          NoteEntry(
            id: 'compact-test-note',
            vaultId: 'everyday',
            title: 'Compact sample',
            body: 'Line one\n\nLine   two',
            createdAt: DateTime(2026, 4, 15, 8, 30),
            updatedAt: DateTime(2026, 4, 15, 8, 31),
            editorMode: NoteEditorMode.quick,
          ),
        );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.view_agenda_outlined).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compact list').last, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(
      container.read(notesListDensityControllerProvider),
      NotesListDensity.compact,
    );
    expect(find.textContaining('Line one Line two'), findsWidgets);

    container.read(appRouterProvider).go('/settings');
    await tester.pumpAndSettle();
    final appearanceHeader = find.textContaining('Appearance');
    await _scrollIntoViewIfNeeded(tester, appearanceHeader);
    await tester.tap(appearanceHeader.first);
    await tester.pumpAndSettle();

    await _scrollIntoViewIfNeeded(
      tester,
      find.byKey(SettingsScreen.localeDropdownKey),
    );
    await tester.tap(find.byKey(SettingsScreen.localeDropdownKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SettingsScreen.localeJapaneseKey));
    await tester.pumpAndSettle();

    expect(
      container.read(appLocaleControllerProvider),
      AppLocaleSetting.japanese,
    );
    expect(find.text('カレンダー'), findsWidgets);
    expect(find.text('記録'), findsWidgets);
    expect(find.text('表示'), findsWidgets);
  });
  testWidgets('tagging a note enables tag-based filtering', (tester) async {
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

    await tester.tap(find.byKey(AppShell.addNoteKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quick memo'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('note-content-input')),
      'Tag flow sample\nBody for tags',
    );
    await tester.pumpAndSettle();

    await _scrollIntoViewIfNeeded(
      tester,
      find.byKey(const Key('note-tag-input')),
    );
    await tester.enterText(find.byKey(const Key('note-tag-input')), 'alpha');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('save-note-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Filters'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('search-tag-input')), 'alpha');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('#alpha'), findsWidgets);
    expect(
      container
          .read(visibleNotesProvider)
          .any((note) => note.title == 'Tag flow sample'),
      isTrue,
    );
  });
}

Future<void> _scrollIntoViewIfNeeded(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isNotEmpty) {
    await tester.ensureVisible(finder.first);
    await tester.pumpAndSettle();
    return;
  }

  final scrollables = find.byType(Scrollable);
  if (scrollables.evaluate().isEmpty) {
    throw StateError('No Scrollable found for $finder');
  }

  final scrollable = scrollables.last;
  for (final direction in const [Offset(0, -240), Offset(0, 240)]) {
    for (
      var attempt = 0;
      attempt < 24 && finder.evaluate().isEmpty;
      attempt++
    ) {
      await tester.drag(scrollable, direction);
      await tester.pumpAndSettle();
    }
    if (finder.evaluate().isNotEmpty) {
      break;
    }
  }
  if (finder.evaluate().isEmpty) {
    throw StateError('Unable to scroll target into view: $finder');
  }
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
}
