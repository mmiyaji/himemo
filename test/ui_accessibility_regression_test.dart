import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/app/app.dart';
import 'package:himemo/app/app_flavor.dart';
import 'package:himemo/features/home/presentation/home_page.dart';
import 'package:himemo/features/home/presentation/home_providers.dart';
import 'package:himemo/features/security/data/encrypted_note_database.dart';
import 'package:himemo/features/security/data/encrypted_note_store.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/master_key_service.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:himemo/l10n/app_localizations.dart';
import 'package:himemo/l10n/app_strings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('all app themes keep primary controls at AA contrast', (
    tester,
  ) async {
    final harness = await _pumpHiMemoApp(
      tester,
      size: const Size(800, 900),
      preferences: const {'settings.locale': 'english'},
    );

    for (final colorTheme in AppColorTheme.values) {
      await harness.container
          .read(appColorThemeControllerProvider.notifier)
          .setTheme(colorTheme);
      await tester.pump();

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      for (final theme in [app.theme!, app.darkTheme!]) {
        final scheme = theme.colorScheme;
        expect(
          _contrastRatio(scheme.primary, scheme.onPrimary),
          greaterThanOrEqualTo(4.5),
          reason:
              '${colorTheme.name} ${scheme.brightness.name} primary controls',
        );
      }
    }
  });

  for (final scenario in const [
    (label: '320px', width: 320.0, textScale: 1.0),
    (label: '360px', width: 360.0, textScale: 1.0),
    (label: '390px', width: 390.0, textScale: 1.0),
    (label: '390px at 200% text', width: 390.0, textScale: 2.0),
  ]) {
    testWidgets('onboarding final actions fit at ${scenario.label}', (
      tester,
    ) async {
      await _pumpHiMemoApp(
        tester,
        size: Size(scenario.width, 844),
        textScale: scenario.textScale,
        preferences: const {'settings.locale': 'english'},
      );

      for (var page = 0; page < 3; page++) {
        final next = find.byKey(const Key('onboarding-next-button'));
        await tester.ensureVisible(next);
        await tester.pump();
        await tester.tap(next);
        await tester.pumpAndSettle();
      }

      final tutorial = find.byKey(const Key('onboarding-tutorial-button'));
      final finish = find.byKey(const Key('onboarding-next-button'));
      expect(tutorial, findsOneWidget);
      expect(finish, findsOneWidget);
      await tester.ensureVisible(finish);
      await tester.pumpAndSettle();

      final screen = Rect.fromLTWH(0, 0, scenario.width, 844);
      final tutorialRect = tester.getRect(tutorial);
      final finishRect = tester.getRect(finish);
      expect(screen.contains(tutorialRect.topLeft), isTrue);
      expect(screen.contains(tutorialRect.bottomRight), isTrue);
      expect(screen.contains(finishRect.topLeft), isTrue);
      expect(screen.contains(finishRect.bottomRight), isTrue);
      expect(tutorialRect.bottom, lessThan(finishRect.top));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('compact settings overview keeps only full-width priorities', (
    tester,
  ) async {
    final harness = await _createHarness(
      preferences: const {'settings.locale': 'english'},
    );
    _configureView(tester, size: const Size(390, 844));
    await _pumpSettingsScreen(tester, harness.container);

    final overview = find.byKey(SettingsScreen.overviewKey);
    final overviewButtons = find.descendant(
      of: overview,
      matching: find.byType(TextButton),
    );
    expect(overviewButtons, findsNWidgets(3));
    for (final element in overviewButtons.evaluate()) {
      final rect = tester.getRect(find.byElementPredicate((e) => e == element));
      expect(rect.width, greaterThan(320));
    }
    expect(
      find.descendant(of: overview, matching: find.text('Profile')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: overview, matching: find.text('App lock')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: overview, matching: find.text('Sync')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: overview, matching: find.text('Memo')),
      findsNothing,
    );
    expect(
      find.descendant(of: overview, matching: find.text('Storage')),
      findsNothing,
    );
    expect(
      find.descendant(of: overview, matching: find.text('Theme')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'an expanded settings group scrolls its controls above navigation',
    (tester) async {
      final harness = await _createHarness(
        preferences: const {'settings.locale': 'english'},
      );
      _configureView(tester, size: const Size(390, 844));
      await _pumpSettingsScreen(
        tester,
        harness.container,
        bottomNavigationBar: const SizedBox(height: 80),
      );

      final storage = find.text('Storage');
      await tester.scrollUntilVisible(storage, 500);
      await tester.drag(find.byType(ListView), const Offset(0, -180));
      await tester.pumpAndSettle();
      final storageTopBeforeExpansion = tester.getRect(storage).top;
      await tester.tap(storage);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(tester.getRect(storage).top, lessThan(storageTopBeforeExpansion));
      final firstStorageControl = find.text('Saved notes on this device');
      expect(firstStorageControl, findsOneWidget);
      expect(tester.getRect(firstStorageControl).bottom, lessThan(764));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'private profile creation rejects passwords below 10 characters',
    (tester) async {
      final harness = await _createHarness(
        preferences: const {'settings.locale': 'english'},
      );
      _configureView(tester, size: const Size(430, 932));
      await _pumpSettingsScreen(tester, harness.container);

      await tester.scrollUntilVisible(find.text('Private profiles'), 300);
      await tester.tap(find.text('Private profiles'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(SettingsScreen.privateProfileAddKey, skipOffstage: false),
      );
      await tester.tap(find.byKey(SettingsScreen.privateProfileAddKey));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(SettingsScreen.privateProfileNameInputKey),
        'Private journal',
      );
      await tester.enterText(
        find.byKey(SettingsScreen.privateProfilePasswordInputKey),
        'short',
      );
      await tester.enterText(
        find.byKey(SettingsScreen.privateProfileConfirmInputKey),
        'short',
      );
      await tester.tap(find.byKey(SettingsScreen.privateProfileSubmitKey));
      await tester.pump();

      expect(find.text('Use at least 10 characters.'), findsOneWidget);
      expect(
        find.byKey(SettingsScreen.privateProfileNameInputKey),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('app lock settings restore fails closed', (tester) async {
    await _pumpHiMemoApp(
      tester,
      size: const Size(390, 844),
      preferences: const {
        'app.onboarding_completed': true,
        'app.onboarding_completed_version': 2,
        'settings.locale': 'english',
      },
      keepAppLockSettingsPending: true,
    );

    expect(
      find.byKey(const Key('app-lock-settings-loading-cover')),
      findsOneWidget,
    );
    expect(find.text('Notes'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('app shell exposes named actions and no placeholder tab', (
    tester,
  ) async {
    await _pumpHiMemoApp(
      tester,
      size: const Size(1024, 900),
      preferences: const {
        'app.onboarding_completed': true,
        'app.onboarding_completed_version': 2,
        'settings.locale': 'english',
      },
    );
    final semantics = tester.ensureSemantics();

    expect(
      tester.getSemantics(find.byKey(AppShell.headerAddNoteKey)),
      isSemantics(
        label: 'Add note',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    final root = RendererBinding
        .instance
        .renderViews
        .single
        .owner!
        .semanticsOwner!
        .rootSemanticsNode!;
    final navigationItems = _semanticsNodes(root)
        .where(
          (node) =>
              node.getSemanticsData().flagsCollection.isSelected !=
              ui.Tristate.none,
        )
        .toList();

    expect(navigationItems, hasLength(4));
    expect(
      navigationItems.map(
        (node) => node.getSemanticsData().label.split('\n').first,
      ),
      containsAll(['Notes', 'Calendar', 'Insights', 'Settings']),
    );
    expect(
      navigationItems.every(
        (node) => node.getSemanticsData().label.trim().isNotEmpty,
      ),
      isTrue,
    );
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });
}

class _TestHarness {
  const _TestHarness({required this.container, required this.database});

  final ProviderContainer container;
  final EncryptedNoteDatabase database;
}

class _PendingAppLockSettingsController extends AppLockSettingsReadyController {
  @override
  void markReady() {}
}

Future<_TestHarness> _createHarness({
  required Map<String, Object> preferences,
  bool keepAppLockSettingsPending = false,
}) async {
  SharedPreferences.setMockInitialValues(preferences);
  configureFlavor(AppFlavor.development);
  final secureStore = MemorySecureKeyValueStore();
  final encryptionService = EncryptionService(random: Random(71));
  final masterKeyService = MasterKeyService(
    secureStore: secureStore,
    keyFactory: encryptionService.generateKeyBytes,
  );
  final database = EncryptedNoteDatabase(executor: NativeDatabase.memory());
  final container = ProviderContainer(
    overrides: [
      packageInfoProvider.overrideWith(
        (ref) async => const AppPackageDetails(
          appName: 'HiMemo',
          version: '0.0.0',
          buildNumber: '0',
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
      if (keepAppLockSettingsPending)
        appLockSettingsReadyProvider.overrideWith(
          _PendingAppLockSettingsController.new,
        ),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(database.close);
  return _TestHarness(container: container, database: database);
}

Future<_TestHarness> _pumpHiMemoApp(
  WidgetTester tester, {
  required Size size,
  required Map<String, Object> preferences,
  double textScale = 1,
  bool keepAppLockSettingsPending = false,
}) async {
  _configureView(tester, size: size, textScale: textScale);
  final harness = await _createHarness(
    preferences: preferences,
    keepAppLockSettingsPending: keepAppLockSettingsPending,
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: const HiMemoApp(flavor: AppFlavor.development),
    ),
  );
  await tester.pump(const Duration(milliseconds: 1200));
  await tester.pumpAndSettle();
  return harness;
}

Future<void> _pumpSettingsScreen(
  WidgetTester tester,
  ProviderContainer container, {
  Widget? bottomNavigationBar,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: const SettingsScreen(),
          bottomNavigationBar: bottomNavigationBar,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 1200));
  await tester.pumpAndSettle();
}

void _configureView(
  WidgetTester tester, {
  required Size size,
  double textScale = 1,
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = max(firstLuminance, secondLuminance);
  final darker = min(firstLuminance, secondLuminance);
  return (lighter + 0.05) / (darker + 0.05);
}

Iterable<SemanticsNode> _semanticsNodes(SemanticsNode root) sync* {
  yield root;
  for (final child in root.debugListChildrenInOrder(
    DebugSemanticsDumpOrder.traversalOrder,
  )) {
    yield* _semanticsNodes(child);
  }
}
