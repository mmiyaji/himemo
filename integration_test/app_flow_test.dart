import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/app/app.dart';
import 'package:himemo/app/app_flavor.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/home/presentation/home_page.dart';
import 'package:himemo/features/home/presentation/home_providers.dart';
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
      'settings.locale': 'english',
    });
    final container = ProviderContainer();
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

    expect(find.text('HiMemo'), findsOneWidget);
    expect(find.byKey(AppShell.addNoteKey), findsOneWidget);

    await _tapNavigation(tester, AppShell.settingsNavKey, 'Settings');
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);

    await _scrollIntoViewIfNeeded(tester, find.text('Appearance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appearance').first);
    await tester.pumpAndSettle();
    expect(find.text('Language'), findsOneWidget);

    await _scrollIntoViewIfNeeded(
      tester,
      find.byKey(SettingsScreen.darkThemeKey),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SettingsScreen.darkThemeKey));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Accent color').first);
    await tester.pumpAndSettle();
    await _scrollIntoViewIfNeeded(
      tester,
      find.byKey(SettingsScreen.greenColorThemeKey),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SettingsScreen.greenColorThemeKey));
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(app.theme?.colorScheme.primary, const Color(0xFF2F6B3C));

    final quickCaptureTile = find.widgetWithText(
      SwitchListTile,
      'Allow external quick capture',
    );
    if (quickCaptureTile.evaluate().isEmpty) {
      final appSecurityHeader = find.text('App security');
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

    await _tapNavigation(tester, AppShell.calendarNavKey, 'Calendar');
    await tester.pumpAndSettle();
    expect(find.textContaining('Review notes grouped by day'), findsOneWidget);

    container.read(widgetQuickCaptureRequestControllerProvider.notifier).open(
      const QuickCaptureRequest(
        nonce: 1,
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
      'settings.locale': 'english',
    });
    final container = ProviderContainer();
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

    await container.read(notesControllerProvider.notifier).upsert(
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

    await _tapNavigation(tester, AppShell.settingsNavKey, 'Settings');
    await tester.pumpAndSettle();
    await _scrollIntoViewIfNeeded(tester, find.text('Appearance'));
    await tester.tap(find.text('Appearance').first);
    await tester.pumpAndSettle();

    await _scrollIntoViewIfNeeded(
      tester,
      find.byKey(SettingsScreen.localeJapaneseKey),
    );
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
      'settings.locale': 'english',
    });
    final container = ProviderContainer();
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

    await _scrollIntoViewIfNeeded(tester, find.byKey(const Key('note-tag-input')));
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
      container.read(visibleNotesProvider).any(
        (note) => note.title == 'Tag flow sample',
      ),
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

  await tester.scrollUntilVisible(
    finder,
    160,
    scrollable: scrollables.first,
  );
  await tester.pumpAndSettle();
}

Future<void> _tapNavigation(
  WidgetTester tester,
  Key preferredKey,
  String label,
) async {
  final keyed = find.byKey(preferredKey);
  if (keyed.evaluate().isNotEmpty) {
    await tester.tap(keyed);
    return;
  }

  await tester.tap(find.text(label).last);
}
