import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/app/app.dart';
import 'package:himemo/app/app_flavor.dart';
import 'package:himemo/app/app_router.dart';
import 'package:himemo/app/play_integrity_service.dart';
import 'package:himemo/app/play_integrity_verifier.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/home/presentation/home_page.dart';
import 'package:himemo/features/home/presentation/home_providers.dart';
import 'package:himemo/features/security/data/encrypted_note_database.dart';
import 'package:himemo/features/sync/presentation/sync_v2_workspace.dart';

import 'package:image_picker/image_picker.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/sync_v2_workspace_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('simulator flow covers auth and v2 note creation', (
    tester,
  ) async {
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
    final fakeDeviceAuthGateway = FakeDeviceAuthGateway(
      authenticateResults: [true, true],
    );
    final fakeMediaImportService = FakeMediaImportService();
    final fakePlayIntegrityVerifier = FakePlayIntegrityVerifier();
    final noteDatabase = EncryptedNoteDatabase(
      executor: NativeDatabase.memory(),
    );
    addTearDown(noteDatabase.close);
    final workspace = (await tester.runAsync(createSyncV2TestWorkspace))!;
    addTearDown(workspace.dispose);
    final container = ProviderContainer(
      overrides: [
        syncV2WorkspaceProvider.overrideWithValue(workspace),
        encryptedNoteDatabaseProvider.overrideWithValue(noteDatabase),
        deviceAuthGatewayProvider.overrideWithValue(fakeDeviceAuthGateway),
        mediaImportServiceProvider.overrideWithValue(fakeMediaImportService),
        playIntegrityVerifierProvider.overrideWithValue(
          fakePlayIntegrityVerifier,
        ),
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

    container.read(appRouterProvider).go('/settings');
    await tester.pumpAndSettle();
    debugPrint('E2E step: settings opened');

    await _expandSettingsSection(tester, 'App security');
    final appLockToggle = find.byKey(SettingsScreen.appLockToggleKey);
    expect(appLockToggle, findsOneWidget);
    await _scrollIntoViewIfNeeded(tester, appLockToggle);
    await tester.tap(appLockToggle);
    await tester.pumpAndSettle();
    debugPrint('E2E step: app lock enabled');

    expect(fakeDeviceAuthGateway.authenticateCallCount, 1);
    expect(container.read(appSessionUnlockControllerProvider), isTrue);

    final quickCaptureTile = find.widgetWithText(
      SwitchListTile,
      'Allow external quick capture',
    );
    expect(quickCaptureTile, findsOneWidget);
    await _scrollIntoViewIfNeeded(tester, quickCaptureTile);
    await tester.tap(quickCaptureTile);
    await tester.pumpAndSettle();
    expect(
      container.read(widgetQuickCaptureSettingsControllerProvider),
      isTrue,
    );

    final lockNow = find.byKey(SettingsScreen.appLockLockNowKey);
    expect(lockNow, findsOneWidget);
    await _scrollIntoViewIfNeeded(tester, lockNow);
    await tester.tap(lockNow);
    await tester.pump(const Duration(milliseconds: 600));
    debugPrint('E2E step: session locked');

    expect(find.text('Unlock HiMemo'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Authenticate').last);
    await tester.pump(const Duration(milliseconds: 800));
    debugPrint('E2E step: lock gate cleared');
    expect(find.text('Unlock HiMemo'), findsNothing);

    container.read(appRouterProvider).go('/notes');
    await tester.pumpAndSettle();
    debugPrint('E2E step: notes opened');

    await container
        .read(lastNoteEditorSettingsControllerProvider.notifier)
        .remember(mode: NoteEditorMode.quick, vaultId: 'everyday');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppShell.addNoteKey));
    await tester.pumpAndSettle();
    await _waitForFinder(tester, find.byKey(const Key('note-content-input')));
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

    container
        .read(widgetQuickCaptureRequestControllerProvider.notifier)
        .open(
          const QuickCaptureRequest(
            nonce: 'integration-share-2',
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
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    final noteTitles = container
        .read(notesControllerProvider)
        .map((note) => note.title)
        .toList();
    expect(
      noteTitles.any((title) => title.contains('Shared simulator note')),
      isTrue,
    );
  });

  testWidgets('v2 settings and app links use a local workspace', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({
      'app.onboarding_completed': true,
      'app.onboarding_completed_version': 2,
      'release_notes.last_seen': '1.0.0+46',
      'settings.locale': 'english',
    });
    final fakePlayIntegrityVerifier = FakePlayIntegrityVerifier();
    final noteDatabase = EncryptedNoteDatabase(
      executor: NativeDatabase.memory(),
    );
    addTearDown(noteDatabase.close);
    final workspace = (await tester.runAsync(createSyncV2TestWorkspace))!;
    addTearDown(workspace.dispose);
    final container = ProviderContainer(
      overrides: [
        syncV2WorkspaceProvider.overrideWithValue(workspace),
        encryptedNoteDatabaseProvider.overrideWithValue(noteDatabase),
        playIntegrityVerifierProvider.overrideWithValue(
          fakePlayIntegrityVerifier,
        ),
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

    container.read(appRouterProvider).go('/settings');
    await tester.pumpAndSettle();

    await _expandSettingsSection(tester, 'Sync and security');
    final beforeSync = workspace.lastSyncCompletedAt;
    final syncNow = find.text('Sync now');
    await _scrollIntoViewIfNeeded(tester, syncNow);
    await tester.tap(syncNow);
    await tester.pump();
    for (
      var attempt = 0;
      attempt < 50 && workspace.lastSyncCompletedAt == beforeSync;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(workspace.lastSyncCompletedAt, isNotNull);
    expect(workspace.lastSyncCompletedAt, isNot(beforeSync));
    expect(find.text('Sync details'), findsNothing);
    expect(find.text('Repair and maintenance'), findsNothing);

    await _expandSettingsSection(tester, 'About');

    await _scrollIntoViewIfNeeded(tester, find.text('Terms of Use'));
    await _openExternalLinkDialogAndCancel(
      tester,
      trigger: find.text('Terms of Use').first,
      expectedUrl: 'https://himemo.ruhenheim.org/terms/',
    );
    await _openExternalLinkDialogAndCancel(
      tester,
      trigger: find.text('Privacy Policy').first,
      expectedUrl: 'https://himemo.ruhenheim.org/privacy/',
    );
    await _openExternalLinkDialogAndCancel(
      tester,
      trigger: find.text('Contact').first,
      expectedUrl: 'https://himemo.ruhenheim.org/#contact',
    );
    await _openExternalLinkDialogAndCancel(
      tester,
      trigger: find.text('Help and FAQ'),
      expectedUrl: 'https://himemo.ruhenheim.org/#usage',
    );
  });

  testWidgets('video attachment share opens Android share sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({
      'app.onboarding_completed': true,
      'app.onboarding_completed_version': 2,
      'release_notes.last_seen': '1.0.0+46',
      'settings.locale': 'english',
    });
    final noteDatabase = EncryptedNoteDatabase(
      executor: NativeDatabase.memory(),
    );
    addTearDown(noteDatabase.close);
    final workspace = (await tester.runAsync(createSyncV2TestWorkspace))!;
    addTearDown(workspace.dispose);
    final container = ProviderContainer(
      overrides: [
        syncV2WorkspaceProvider.overrideWithValue(workspace),
        encryptedNoteDatabaseProvider.overrideWithValue(noteDatabase),
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

    final source = File('${Directory.systemTemp.path}/himemo-share-test.mp4');
    await source.writeAsBytes(<int>[
      0,
      0,
      0,
      24,
      102,
      116,
      121,
      112,
      109,
      112,
      52,
      50,
    ]);
    final attachmentStore = container.read(encryptedAttachmentStoreProvider);
    final storedPath = await attachmentStore.storeAttachment(
      XFile(source.path, name: 'himemo-share-test.mp4', mimeType: 'video/mp4'),
      type: AttachmentType.video,
    );
    expect(storedPath, isNotNull);
    final attachment = NoteAttachment(
      type: AttachmentType.video,
      label: 'himemo-share-test.mp4',
      filePath: storedPath,
    );

    await container
        .read(notesControllerProvider.notifier)
        .upsert(
          NoteEntry(
            id: 'android-share-video-note',
            vaultId: 'everyday',
            title: 'Android share video note',
            body: 'Video attachment share verification.',
            createdAt: DateTime.utc(2026, 5, 13, 0, 0),
            updatedAt: DateTime.utc(2026, 5, 13, 0, 1),
            attachments: [attachment],
            editorMode: NoteEditorMode.quick,
          ),
        );
    await tester.pumpAndSettle();

    container.read(appRouterProvider).go('/notes');
    await tester.pumpAndSettle();
    await _scrollIntoViewIfNeeded(
      tester,
      find.text('Android share video note'),
    );
    await tester.tap(find.text('Android share video note').first);
    await tester.pumpAndSettle();

    await _waitForFinder(tester, find.byTooltip('Share'));
    await tester.tap(find.byTooltip('Share').last, warnIfMissed: false);
    await tester.pump(const Duration(seconds: 3));
    debugPrint('E2E step: video attachment share tapped');
  });
}

Future<void> _expandSettingsSection(WidgetTester tester, String title) async {
  final header = find.text(title);
  await _scrollIntoViewIfNeeded(tester, header);
  expect(header, findsOneWidget);
  final tile = tester.widget<ExpansionTile>(
    find.ancestor(of: header, matching: find.byType(ExpansionTile)).first,
  );
  expect(tile.controller, isNotNull);
  if (!tile.controller!.isExpanded) {
    await tester.tap(header);
    await tester.pumpAndSettle();
  }
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

  final scrollable = scrollables.last;
  for (final direction in const [Offset(0, -240), Offset(0, 240)]) {
    for (
      var attempt = 0;
      attempt < 24 && finder.evaluate().isEmpty;
      attempt++
    ) {
      await tester.drag(scrollable, direction);
      await tester.pumpAndSettle();
    }
    if (finder.evaluate().isNotEmpty) {
      break;
    }
  }
  if (finder.evaluate().isEmpty) {
    throw StateError('Unable to scroll target into view: $finder');
  }
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
}

Future<void> _waitForFinder(
  WidgetTester tester,
  Finder finder, {
  int attempts = 10,
}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    if (finder.evaluate().isNotEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(finder, findsOneWidget);
}

Future<void> _openExternalLinkDialogAndCancel(
  WidgetTester tester, {
  required Finder trigger,
  required String expectedUrl,
}) async {
  await _scrollIntoViewIfNeeded(tester, trigger);
  final tile = find.ancestor(
    of: trigger.first,
    matching: find.byType(ListTile),
  );
  await tester.tap(tile.evaluate().isEmpty ? trigger.first : tile.first);
  await tester.pumpAndSettle();
  expect(find.text('Open external link?'), findsOneWidget);
  expect(find.text(expectedUrl), findsOneWidget);
  await tester.tap(find.text('Cancel').last);
  await tester.pumpAndSettle();
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

class FakeMediaImportService implements MediaImportService {
  int importCallCount = 0;

  @override
  Future<MediaImportResult> importAttachment(
    MediaImportAction action, {
    VoidCallback? onProcessingStarted,
  }) async {
    importCallCount += 1;
    onProcessingStarted?.call();
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
      MediaImportAction.recordAudio ||
      MediaImportAction.pickAudio => const MediaImportResult.success(
        NoteAttachment(
          type: AttachmentType.audio,
          label: 'simulator-audio.m4a',
        ),
      ),
      MediaImportAction.pickFile => const MediaImportResult.success(
        NoteAttachment(type: AttachmentType.file, label: 'simulator-file.pdf'),
      ),
      MediaImportAction.addLocation => const MediaImportResult.failure(
        'Location insertion is handled by the note editor.',
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
    return const PlayIntegrityVerificationResult(allowed: true, message: 'ok');
  }
}
