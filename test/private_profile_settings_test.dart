import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/app/app_flavor.dart';
import 'package:himemo/features/home/presentation/home_page.dart';
import 'package:himemo/features/home/presentation/home_providers.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:himemo/features/sync/presentation/sync_v2_workspace.dart';
import 'package:himemo/l10n/app_localizations.dart';
import 'package:himemo/l10n/app_strings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/sync_v2_workspace_fixture.dart';

void main() {
  testWidgets('profile setup accepts a four-character numeric passcode', (
    tester,
  ) async {
    await _pumpSettings(tester);
    await tester.ensureVisible(find.byKey(SettingsScreen.privateProfileAddKey));
    await tester.tap(find.byKey(SettingsScreen.privateProfileAddKey));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.byType(SegmentedButton<bool>)),
      findsNothing,
    );

    final password = find.byKey(SettingsScreen.privateProfilePasswordInputKey);
    final confirmation = find.byKey(
      SettingsScreen.privateProfileConfirmInputKey,
    );
    final form = tester.state<FormState>(
      find.descendant(of: dialog, matching: find.byType(Form)),
    );
    await tester.enterText(password, '123');
    await tester.enterText(confirmation, '123');
    expect(form.validate(), isFalse);
    await tester.pump();
    expect(find.text('Use at least 4 characters.'), findsOneWidget);

    await tester.enterText(password, '5678');
    await tester.enterText(confirmation, '5678');
    expect(form.validate(), isTrue);
    await tester.pump();
    expect(find.text('Use at least 4 characters.'), findsNothing);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'administrator profile rows open v2 profiles and share one menu',
    (tester) async {
      final container = await _pumpSettings(tester, createProfile: true);
      final profile = container.read(privateMemoProfilesProvider).single;
      final row = find.byKey(SettingsScreen.privateProfileOpenKey(profile.id));
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(
        container.read(searchFiltersControllerProvider).vaultId,
        profile.vaultId,
      );
      expect(find.byType(AlertDialog), findsNothing);
      expect(container.read(adminModeSessionControllerProvider), isTrue);

      await tester.tap(
        find.byKey(SettingsScreen.privateProfileMenuKey(profile.id)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Rename profile'), findsOneWidget);
      expect(find.text('Delete profile'), findsOneWidget);
      expect(find.text('Set device PIN'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<ProviderContainer> _pumpSettings(
  WidgetTester tester, {
  bool createProfile = false,
}) async {
  tester.view.physicalSize = const Size(1100, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'settings.locale': 'english'});
  configureFlavor(AppFlavor.development);
  final workspace = (await tester.runAsync(createSyncV2TestWorkspace))!;
  addTearDown(workspace.dispose);
  final container = ProviderContainer(
    overrides: [
      syncV2WorkspaceProvider.overrideWithValue(workspace),
      secureKeyValueStoreProvider.overrideWithValue(
        MemorySecureKeyValueStore(),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.runAsync(() async {
    await container.read(notesControllerProvider.notifier).restoreCompleted;
    if (createProfile) {
      await container
          .read(adminModeSessionControllerProvider.notifier)
          .unlockWithAdminPassword('1234');
      await workspace.createProfile('Work', '5678');
      await container
          .read(privateMemoProfilesControllerProvider.notifier)
          .refresh();
    }
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SettingsScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (find.byKey(SettingsScreen.privateProfileAddKey).evaluate().isEmpty) {
    await tester.ensureVisible(find.text('Private profiles'));
    await tester.tap(find.text('Private profiles'));
    await tester.pumpAndSettle();
  }
  return container;
}
