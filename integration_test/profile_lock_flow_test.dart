import 'package:flutter/material.dart';
import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/app/app.dart';
import 'package:himemo/app/app_flavor.dart';
import 'package:himemo/app/app_router.dart';
import 'package:himemo/features/home/presentation/home_page.dart';
import 'package:himemo/features/home/presentation/home_providers.dart';
import 'package:himemo/features/security/data/encrypted_note_database.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'device auth stays single-flight while lifecycle changes during unlock',
    (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues({
        'app.onboarding_completed': true,
        'app.onboarding_completed_version': 2,
        'release_notes.last_seen': '1.0.0+46',
        'settings.locale': 'english',
        'settings.app_lock_enabled': true,
        'settings.app_lock_relock_delay': 'immediate',
      });
      final fakeDeviceAuthGateway = _DelayedDeviceAuthGateway();
      final noteDatabase = EncryptedNoteDatabase(
        executor: NativeDatabase.memory(),
      );
      addTearDown(noteDatabase.close);
      final container = ProviderContainer(
        overrides: [
          encryptedNoteDatabaseProvider.overrideWithValue(noteDatabase),
          deviceAuthGatewayProvider.overrideWithValue(fakeDeviceAuthGateway),
        ],
      );
      addTearDown(container.dispose);

      configureFlavor(AppFlavor.development);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TooltipVisibility(
            visible: false,
            child: HiMemoApp(flavor: AppFlavor.development),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pump();

      expect(find.text('Unlock HiMemo'), findsOneWidget);
      expect(fakeDeviceAuthGateway.authenticateCallCount, 1);
      expect(
        container.read(deviceAuthControllerProvider).isAuthenticating,
        isTrue,
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(fakeDeviceAuthGateway.authenticateCallCount, 1);
      expect(
        container.read(deviceAuthControllerProvider).isAuthenticating,
        isTrue,
      );

      fakeDeviceAuthGateway.complete(true);
      await _pumpUi(tester);

      expect(fakeDeviceAuthGateway.authenticateCallCount, 1);
      expect(container.read(appSessionUnlockControllerProvider), isTrue);
      expect(find.text('Unlock HiMemo'), findsNothing);
    },
  );

  testWidgets(
    'private profiles unlock hidden save targets and app relock closes them again',
    (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues({
        'app.onboarding_completed': true,
        'app.onboarding_completed_version': 2,
        'release_notes.last_seen': '1.0.0+46',
        'settings.locale': 'english',
        'notes.last_editor_mode': 'quick',
      });
      final fakeDeviceAuthGateway = _FakeDeviceAuthGateway(
        authenticateResults: [true, true],
      );
      final noteDatabase = EncryptedNoteDatabase(
        executor: NativeDatabase.memory(),
      );
      addTearDown(noteDatabase.close);
      final container = ProviderContainer(
        overrides: [
          encryptedNoteDatabaseProvider.overrideWithValue(noteDatabase),
          deviceAuthGatewayProvider.overrideWithValue(fakeDeviceAuthGateway),
        ],
      );
      addTearDown(container.dispose);

      configureFlavor(AppFlavor.development);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TooltipVisibility(
            visible: false,
            child: HiMemoApp(flavor: AppFlavor.development),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1200));
      await _pumpUi(tester);

      final noteTitle =
          'Private profile E2E note ${DateTime.now().microsecondsSinceEpoch}';
      final addError = await container
          .read(privateMemoProfilesControllerProvider.notifier)
          .addProfile(name: 'Cover profile', password: 'cover-pass-123');
      expect(addError, isNull);
      await _pumpUi(tester);
      expect(container.read(privateMemoProfilesProvider).length, 1);

      container.read(appRouterProvider).go('/notes');
      await _pumpUi(tester);

      final unlocked = await container
          .read(privateProfileUnlockControllerProvider.notifier)
          .unlockWithPassword('cover-pass-123');
      await _pumpUi(tester);
      final unlockedVaultId = container.read(
        unlockedPrivateProfileVaultIdProvider,
      );
      expect(unlocked, isNotNull);
      expect(unlockedVaultId, startsWith(customPrivateVaultPrefix));
      expect(
        container.read(accessiblePrivateVaultIdsProvider),
        contains(unlockedVaultId),
      );

      await tester.tap(find.byKey(AppShell.addNoteKey));
      await _pumpUi(tester);
      await _ensureQuickMemoEditor(tester);
      final privateToggle = find.byKey(const Key('note-save-private-toggle'));
      await _scrollIntoViewIfNeeded(tester, privateToggle);
      await tester.tap(privateToggle);
      await _pumpUi(tester);
      await tester.enterText(
        find.byKey(const Key('note-content-input')),
        '$noteTitle\nSaved on an unlocked profile',
      );
      final saveButton = find.byKey(const Key('save-note-button'));
      await _scrollIntoViewIfNeeded(tester, saveButton);
      await tester.tap(saveButton);
      await _pumpUi(tester);

      expect(
        container.read(visibleNotesProvider).map((note) => note.title),
        contains(noteTitle),
      );
      await _scrollIntoViewIfNeeded(tester, find.text(noteTitle));
      await _pumpUi(tester);
      expect(find.text(noteTitle), findsWidgets);

      container.read(appRouterProvider).go('/settings');
      await _pumpUi(tester);

      await _scrollIntoViewIfNeeded(tester, find.text('App security'));
      await tester.tap(find.text('App security').first);
      await _pumpUi(tester);

      final appLockToggle = find.byKey(SettingsScreen.appLockToggleKey);
      await _scrollIntoViewIfNeeded(tester, appLockToggle);
      await tester.tap(appLockToggle);
      await _pumpUi(tester);
      expect(fakeDeviceAuthGateway.authenticateCallCount, 1);

      final lockNowButton = find.byKey(SettingsScreen.appLockLockNowKey);
      await _scrollIntoViewIfNeeded(tester, lockNowButton);
      await tester.tap(lockNowButton);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Unlock HiMemo'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Authenticate').last);
      await tester.pump(const Duration(milliseconds: 800));
      await _pumpUi(tester);

      expect(container.read(unlockedPrivateProfileVaultIdProvider), isNull);
      expect(container.read(adminModeSessionControllerProvider), isFalse);
      expect(fakeDeviceAuthGateway.authenticateCallCount, 2);

      container.read(appRouterProvider).go('/notes');
      await _pumpUi(tester);
      await tester.tap(find.byKey(AppShell.addNoteKey));
      await _pumpUi(tester);
      expect(find.byKey(const Key('note-save-private-toggle')), findsNothing);
    },
  );
}

Future<void> _scrollIntoViewIfNeeded(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isNotEmpty) {
    await tester.ensureVisible(finder.first);
    await _pumpUi(tester);
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
      await _pumpUi(tester);
    }
    if (finder.evaluate().isNotEmpty) {
      break;
    }
  }
  if (finder.evaluate().isEmpty) {
    throw StateError('Unable to scroll target into view: $finder');
  }
  await tester.ensureVisible(finder.first);
  await _pumpUi(tester);
}

Future<void> _ensureQuickMemoEditor(WidgetTester tester) async {
  final quickInput = find.byKey(const Key('note-content-input'));
  if (quickInput.evaluate().isNotEmpty) {
    return;
  }

  final richMemoButton = find.text('Rich memo');
  if (richMemoButton.evaluate().isNotEmpty) {
    await tester.tap(richMemoButton.last);
    await _pumpUi(tester);
  }

  final quickMemoButton = find.text('Quick memo');
  if (quickMemoButton.evaluate().isNotEmpty) {
    await tester.tap(quickMemoButton.last);
    await _pumpUi(tester);
  }

  await _scrollIntoViewIfNeeded(tester, quickInput);
}

Future<void> _pumpUi(
  WidgetTester tester, [
  Duration duration = const Duration(milliseconds: 300),
]) async {
  await tester.pump(duration);
  await tester.pump(duration);
}

class _FakeDeviceAuthGateway implements DeviceAuthGateway {
  _FakeDeviceAuthGateway({required List<bool> authenticateResults})
    : _authenticateResults = List<bool>.from(authenticateResults);

  final List<bool> _authenticateResults;
  int authenticateCallCount = 0;

  @override
  Future<bool> authenticate({
    required String reason,
    bool biometricOnly = false,
  }) async {
    authenticateCallCount += 1;
    if (_authenticateResults.isEmpty) {
      return true;
    }
    return _authenticateResults.removeAt(0);
  }

  @override
  Future<DeviceAuthState> checkAvailability() async {
    return const DeviceAuthState(
      availability: DeviceAuthAvailability.available,
      methods: ['Fingerprint', 'Device credential'],
    );
  }
}

class _DelayedDeviceAuthGateway implements DeviceAuthGateway {
  final Completer<bool> _authenticateCompleter = Completer<bool>();
  int authenticateCallCount = 0;

  @override
  Future<bool> authenticate({
    required String reason,
    bool biometricOnly = false,
  }) {
    authenticateCallCount += 1;
    return _authenticateCompleter.future;
  }

  @override
  Future<DeviceAuthState> checkAvailability() async {
    return const DeviceAuthState(
      availability: DeviceAuthAvailability.available,
      methods: ['Fingerprint', 'Device credential'],
    );
  }

  void complete(bool value) {
    if (_authenticateCompleter.isCompleted) {
      return;
    }
    _authenticateCompleter.complete(value);
  }
}
