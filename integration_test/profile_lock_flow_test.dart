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

  testWidgets(
    'private profiles unlock hidden save targets and app relock closes them again',
    (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues({
        'app.onboarding_completed': true,
        'settings.locale': 'english',
      });
      final fakeDeviceAuthGateway = _FakeDeviceAuthGateway(
        authenticateResults: [true, true],
      );
      final container = ProviderContainer(
        overrides: [
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
      await tester.pumpAndSettle();

      final addError = await container
          .read(privateMemoProfilesControllerProvider.notifier)
          .addProfile(name: 'Cover profile', password: 'cover-pass-123');
      expect(addError, isNull);
      await tester.pumpAndSettle();
      expect(container.read(privateMemoProfilesProvider).length, 1);

      await _tapNavigation(tester, AppShell.notesNavKey, 'Notes');
      await tester.pumpAndSettle();

      final unlocked = await container
          .read(privateProfileUnlockControllerProvider.notifier)
          .unlockWithPassword('cover-pass-123');
      await tester.pumpAndSettle();
      final unlockedVaultId = container.read(unlockedPrivateProfileVaultIdProvider);
      expect(unlocked, isNotNull);
      expect(unlockedVaultId, startsWith(customPrivateVaultPrefix));
      expect(
        container.read(accessiblePrivateVaultIdsProvider),
        contains(unlockedVaultId),
      );

      await _tapNavigation(tester, AppShell.settingsNavKey, 'Settings');
      await tester.pumpAndSettle();

      final appLockToggle = find.byKey(SettingsScreen.appLockToggleKey);
      await _scrollIntoViewIfNeeded(tester, appLockToggle);
      await tester.tap(appLockToggle);
      await tester.pumpAndSettle();
      expect(fakeDeviceAuthGateway.authenticateCallCount, 1);

      final lockNowButton = find.byKey(SettingsScreen.appLockLockNowKey);
      await _scrollIntoViewIfNeeded(tester, lockNowButton);
      await tester.tap(lockNowButton);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Unlock HiMemo'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Authenticate').last);
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();

      expect(container.read(unlockedPrivateProfileVaultIdProvider), isNull);
      expect(container.read(adminModeSessionControllerProvider), isFalse);
      expect(fakeDeviceAuthGateway.authenticateCallCount, 2);

      await _tapNavigation(tester, AppShell.notesNavKey, 'Notes');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AppShell.addNoteKey));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('note-save-private-toggle')), findsNothing);
    },
  );
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
