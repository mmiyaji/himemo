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

  testWidgets('simulator flow covers auth, sync, and note creation', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'app.onboarding_completed': true,
      'settings.locale': 'english',
    });
    final fakeDeviceAuthGateway = FakeDeviceAuthGateway(
      authenticateResults: [true, true],
    );
    final fakeSyncAuthGateway = FakeSyncAuthGateway();
    final fakeMediaImportService = FakeMediaImportService();
    final container = ProviderContainer(
      overrides: [
        deviceAuthGatewayProvider.overrideWithValue(fakeDeviceAuthGateway),
        syncAuthGatewayProvider.overrideWithValue(fakeSyncAuthGateway),
        mediaImportServiceProvider.overrideWithValue(fakeMediaImportService),
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
    debugPrint('E2E step: app launched');

    await _tapNavigation(tester, AppShell.settingsNavKey, 'Settings');
    await tester.pumpAndSettle();
    debugPrint('E2E step: settings opened');

    expect(find.byKey(SettingsScreen.appLockToggleKey), findsOneWidget);
    await tester.tap(find.byKey(SettingsScreen.appLockToggleKey));
    await tester.pumpAndSettle();
    debugPrint('E2E step: app lock enabled');

    expect(fakeDeviceAuthGateway.authenticateCallCount, 1);
    expect(find.textContaining('Current session is unlocked'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.widgetWithText(SwitchListTile, 'Allow external quick capture'),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(SwitchListTile, 'Allow external quick capture'),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(SettingsScreen.syncGoogleDriveKey),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SettingsScreen.syncGoogleDriveKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SettingsScreen.syncConnectKey));
    await tester.pumpAndSettle();
    debugPrint('E2E step: sync connected');

    expect(fakeSyncAuthGateway.connectCalls, [SyncProvider.googleDrive]);
    expect(find.textContaining('simulator@example.com'), findsWidgets);

    final lockNowFinder = find.byKey(SettingsScreen.appLockLockNowKey);
    for (
      var attempt = 0;
      attempt < 4 && lockNowFinder.evaluate().isEmpty;
      attempt++
    ) {
      await tester.drag(find.byType(Scrollable).last, const Offset(0, 320));
      await tester.pumpAndSettle();
    }
    expect(lockNowFinder, findsOneWidget);
    await tester.tap(lockNowFinder);
    await tester.pump(const Duration(milliseconds: 600));
    debugPrint('E2E step: session locked');

    expect(find.text('Unlock HiMemo'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Authenticate').last);
    await tester.pump(const Duration(milliseconds: 800));
    debugPrint('E2E step: lock gate cleared');
    expect(find.text('Unlock HiMemo'), findsNothing);

    await _tapNavigation(tester, AppShell.notesNavKey, 'Notes');
    await tester.pumpAndSettle();
    debugPrint('E2E step: notes opened');

    await tester.tap(find.byKey(AppShell.addNoteKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quick memo').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('note-content-input')),
      'Simulator attachment note\nCreated in mobile integration test.',
    );
    await tester.pumpAndSettle();
    debugPrint('E2E step: note body entered');

    await tester.tap(find.byKey(const Key('save-note-button')));
    await tester.pumpAndSettle();
    debugPrint('E2E step: note saved');

    expect(find.text('Simulator attachment note'), findsOneWidget);

    container.read(widgetQuickCaptureRequestControllerProvider.notifier).open(
      const QuickCaptureRequest(
        nonce: 2,
        source: QuickCaptureSource.share,
        initialText: 'Shared simulator note',
      ),
    );
    await tester.pumpAndSettle();
    debugPrint('E2E step: external quick capture opened');

    expect(find.byKey(const Key('widget-quick-capture-input')), findsOneWidget);
    await tester.tap(find.byKey(const Key('widget-quick-capture-submit')));
    await tester.pumpAndSettle();
    debugPrint('E2E step: external quick capture saved');

    expect(find.textContaining('Shared simulator note'), findsWidgets);
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

class FakeDeviceAuthGateway implements DeviceAuthGateway {
  FakeDeviceAuthGateway({required List<bool> authenticateResults})
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

class FakeSyncAuthGateway implements SyncAuthGateway {
  final List<SyncProvider> connectCalls = [];

  @override
  Future<SyncAuthState> connect(SyncProvider provider) async {
    connectCalls.add(provider);
    return const SyncAuthState(
      provider: SyncProvider.googleDrive,
      stage: SyncAuthStage.authenticated,
      userId: 'sim-google-user',
      displayName: 'Simulator Account',
      email: 'simulator@example.com',
      message: 'Simulator Google Drive account is connected.',
    );
  }

  @override
  Future<void> disconnect(SyncProvider provider) async {}
}

class FakeMediaImportService implements MediaImportService {
  int importCallCount = 0;

  @override
  Future<MediaImportResult> importAttachment(MediaImportAction action) async {
    importCallCount += 1;
    return switch (action) {
      MediaImportAction.takePhoto ||
      MediaImportAction.pickPhoto => const MediaImportResult.success(
        NoteAttachment(
          type: AttachmentType.photo,
          label: 'simulator-photo.jpg',
        ),
      ),
      MediaImportAction.recordVideo ||
      MediaImportAction.pickVideo => const MediaImportResult.success(
        NoteAttachment(
          type: AttachmentType.video,
          label: 'simulator-video.mp4',
        ),
      ),
      MediaImportAction.pickAudio => const MediaImportResult.success(
        NoteAttachment(
          type: AttachmentType.audio,
          label: 'simulator-audio.m4a',
        ),
      ),
    };
  }
}
