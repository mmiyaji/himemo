import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/app/app.dart';
import 'package:himemo/app/app_flavor.dart';
import 'package:himemo/features/home/presentation/home_page.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('core navigation and theme flow works', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    configureFlavor(AppFlavor.development);
    await tester.pumpWidget(
      const ProviderScope(child: HiMemoApp(flavor: AppFlavor.development)),
    );
    await tester.pumpAndSettle();

    expect(find.text('HiMemo'), findsOneWidget);
    expect(find.byKey(AppShell.addNoteKey), findsOneWidget);

    await _tapNavigation(tester, AppShell.settingsNavKey, 'Settings');
    await tester.pumpAndSettle();
    expect(find.text('Lock profiles'), findsOneWidget);
    expect(find.text('Storage'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(SettingsScreen.darkThemeKey),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SettingsScreen.darkThemeKey));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(SettingsScreen.greenColorThemeKey),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SettingsScreen.greenColorThemeKey));
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(app.theme?.colorScheme.primary, const Color(0xFF2F6B3C));

    await _tapNavigation(tester, AppShell.notesNavKey, 'Notes');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('note-tile-n1')), findsOneWidget);

    await tester.tap(find.byKey(AppShell.profileSwitchKey));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Private View').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('note-tile-n4')), findsOneWidget);
    expect(find.text('Private View'), findsOneWidget);

    await _tapNavigation(tester, AppShell.calendarNavKey, 'Calendar');
    await tester.pumpAndSettle();
    expect(find.textContaining('Review notes grouped by day'), findsOneWidget);
  });
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
