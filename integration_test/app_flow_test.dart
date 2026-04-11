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
    expect(find.text('Daily View'), findsOneWidget);

    await _tapNavigation(tester, AppShell.settingsNavKey, 'Settings');
    await tester.pumpAndSettle();
    expect(find.text('Manage lock profiles, sync, and display policy.'),
        findsOneWidget);

    await tester.tap(find.byKey(SettingsScreen.darkThemeKey));
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);

    await _tapNavigation(tester, AppShell.notesNavKey, 'Notes');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('note-tile-n1')), findsOneWidget);

    await tester.tap(find.byKey(AppShell.profileSwitchKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Private View'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('note-tile-n4')), findsOneWidget);
    expect(find.text('Private View'), findsOneWidget);

    await _tapNavigation(tester, AppShell.calendarNavKey, 'Calendar');
    await tester.pumpAndSettle();
    expect(find.text('Review notes grouped by day.'), findsOneWidget);
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
