import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/app/app.dart';
import 'package:himemo/app/app_flavor.dart';
import 'package:himemo/features/home/presentation/home_page.dart';
import 'package:himemo/features/home/presentation/home_providers.dart';
import 'package:patrol/patrol.dart';

void main() {
  patrolTest('private profile unlock reveals hidden save target on mobile', ($) async {
    final fakeDeviceAuthGateway = _FakeDeviceAuthGateway(
      authenticateResults: [true],
    );
    final container = ProviderContainer(
      overrides: [
        deviceAuthGatewayProvider.overrideWithValue(fakeDeviceAuthGateway),
      ],
    );
    addTearDown(container.dispose);

    configureFlavor(AppFlavor.development);
    await $.pumpWidgetAndSettle(
      UncontrolledProviderScope(
        container: container,
        child: const HiMemoApp(flavor: AppFlavor.development),
      ),
    );
    await container.read(appLaunchControllerProvider.notifier).completeOnboarding();
    await $.pumpAndSettle();

    await $(find.byKey(AppShell.settingsNavKey)).tap();
    await $(find.byKey(SettingsScreen.privateProfileAddKey)).tap();
    await $(find.byKey(SettingsScreen.privateProfileNameInputKey)).enterText(
      'Patrol profile',
    );
    await $(find.byKey(SettingsScreen.privateProfilePasswordInputKey)).enterText(
      'patrol-pass-123',
    );
    await $(find.byKey(SettingsScreen.privateProfileConfirmInputKey)).enterText(
      'patrol-pass-123',
    );
    await $(find.byKey(SettingsScreen.privateProfileSubmitKey)).tap();
    await $('Patrol profile').waitUntilVisible();

    await $(find.byKey(AppShell.notesNavKey)).tap();
    await $(find.byKey(AppShell.addNoteKey)).tap();
    expect($(find.byKey(const Key('note-save-private-toggle'))), findsNothing);
    await $('Cancel').tap();

    await $(find.byKey(AppShell.privateProfileAccessKey)).tap();
    await $(find.byKey(const Key('private-profile-unlock-password-input')))
        .enterText('patrol-pass-123');
    await $(find.byKey(const Key('private-profile-unlock-submit'))).tap();

    await $(find.byKey(AppShell.addNoteKey)).tap();
    await $('Quick memo').tap();
    await $(find.byKey(const Key('note-save-private-toggle'))).waitUntilVisible();
  });
}

class _FakeDeviceAuthGateway implements DeviceAuthGateway {
  _FakeDeviceAuthGateway({required List<bool> authenticateResults})
      : _authenticateResults = List<bool>.from(authenticateResults);

  final List<bool> _authenticateResults;

  @override
  Future<bool> authenticate({
    required String reason,
    bool biometricOnly = false,
  }) async {
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
