import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/app/app.dart';
import 'package:himemo/app/app_flavor.dart';
import 'package:himemo/app/play_integrity_service.dart';
import 'package:himemo/app/play_integrity_verifier.dart';
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
    final fakePlayIntegrityVerifier = FakePlayIntegrityVerifier();
    final container = ProviderContainer(
      overrides: [
        deviceAuthGatewayProvider.overrideWithValue(fakeDeviceAuthGateway),
        syncAuthGatewayProvider.overrideWithValue(fakeSyncAuthGateway),
        mediaImportServiceProvider.overrideWithValue(fakeMediaImportService),
        playIntegrityVerifierProvider.overrideWithValue(fakePlayIntegrityVerifier),
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

    if (find.byKey(SettingsScreen.appLockToggleKey).evaluate().isEmpty) {
      final appSecurityHeader = find.text('App security');
      if (appSecurityHeader.evaluate().isNotEmpty) {
        await _scrollIntoViewIfNeeded(tester, appSecurityHeader);
        await tester.tap(appSecurityHeader.first);
        await tester.pumpAndSettle();
      }
    }

    final appLockToggle = find.byKey(SettingsScreen.appLockToggleKey);
    if (appLockToggle.evaluate().isNotEmpty) {
      await tester.tap(appLockToggle);
      await tester.pumpAndSettle();
    } else {
      await container
          .read(deviceAuthControllerProvider.notifier)
          .authenticate(reason: 'Enable device authentication for HiMemo');
      await container
          .read(appLockSettingsControllerProvider.notifier)
          .setEnabled(true);
      await tester.pumpAndSettle();
    }
    debugPrint('E2E step: app lock enabled');

    expect(fakeDeviceAuthGateway.authenticateCallCount, 1);
    expect(container.read(appSessionUnlockControllerProvider), isTrue);

    await _scrollIntoViewIfNeeded(
      tester,
      find.widgetWithText(SwitchListTile, 'Allow external quick capture'),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(SwitchListTile, 'Allow external quick capture'),
    );
    await tester.pumpAndSettle();

    await _scrollIntoViewIfNeeded(
      tester,
      find.byKey(SettingsScreen.syncGoogleDriveKey),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SettingsScreen.syncGoogleDriveKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SettingsScreen.syncConnectKey));
    await tester.pumpAndSettle();
    debugPrint('E2E step: sync connected');

    expect(fakeSyncAuthGateway.connectCalls, [SyncProvider.googleDrive]);
    expect(fakePlayIntegrityVerifier.operations, ['sync.enable']);
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
    await tester.ensureVisible(lockNowFinder);
    await tester.pumpAndSettle();
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

    expect(find.text('Simulator attachment note'), findsWidgets);

    container.read(widgetQuickCaptureRequestControllerProvider.notifier).open(
      const QuickCaptureRequest(
        nonce: 2,
        source: QuickCaptureSource.share,
        initialText: 'Shared simulator note',
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));
    debugPrint('E2E step: external quick capture opened');

    expect(find.byKey(const Key('widget-quick-capture-input')), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('widget-quick-capture-submit')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(
      find.byKey(const Key('widget-quick-capture-submit')),
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 900));
    debugPrint('E2E step: external quick capture saved');

    final noteTitles = container
        .read(notesControllerProvider)
        .map((note) => note.title)
        .toList();
    expect(
      noteTitles.any((title) => title.contains('Shared simulator note')),
      isTrue,
    );
  });
}

Future<void> _scrollIntoViewIfNeeded(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isNotEmpty) {
    await tester.ensureVisible(finder);
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

class FakePlayIntegrityVerifier extends PlayIntegrityVerifier {
  FakePlayIntegrityVerifier()
    : super(playIntegrityService: const PlayIntegrityService());

  final List<String> operations = [];

  @override
  Future<PlayIntegrityVerificationResult> verifyOperation({
    required AppFlavor flavor,
    required String operation,
    Map<String, Object?> payload = const <String, Object?>{},
  }) async {
    operations.add(operation);
    return const PlayIntegrityVerificationResult(
      allowed: true,
      message: 'ok',
    );
  }
}
