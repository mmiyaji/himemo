import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/app/app.dart';
import 'package:himemo/app/app_flavor.dart';
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

    await tester.scrollUntilVisible(
      find.text('Appearance'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appearance').first);
    await tester.pumpAndSettle();
    expect(find.text('Language'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(SettingsScreen.darkThemeKey),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SettingsScreen.darkThemeKey));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Accent color').first);
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

    await tester.scrollUntilVisible(
      find.widgetWithText(SwitchListTile, 'Allow external quick capture'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(SwitchListTile, 'Allow external quick capture'),
    );
    await tester.pumpAndSettle();

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
    expect(find.textContaining('Shared note from integration test'), findsWidgets);
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
