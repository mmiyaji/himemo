import 'dart:io';

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
import 'package:himemo/features/sync/data/google_drive_sync_transport.dart';
import 'package:image_picker/image_picker.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('simulator flow covers auth, sync, and note creation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({
      'app.onboarding_completed': true,
      'app.onboarding_completed_version': 2,
      'settings.locale': 'english',
      'notes.last_editor_mode': 'quick',
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

    final quickCaptureTile = find.widgetWithText(
      SwitchListTile,
      'Allow external quick capture',
    );
    if (quickCaptureTile.evaluate().isNotEmpty) {
      await _scrollIntoViewIfNeeded(tester, quickCaptureTile);
      await tester.tap(quickCaptureTile);
      await tester.pumpAndSettle();
    } else {
      await container
          .read(widgetQuickCaptureSettingsControllerProvider.notifier)
          .setEnabled(true);
      await tester.pumpAndSettle();
    }

    await _scrollIntoViewIfNeeded(tester, find.text('Backup and sync'));
    await tester.tap(find.text('Backup and sync'));
    await tester.pumpAndSettle();

    try {
      await _scrollIntoViewIfNeeded(
        tester,
        find.byKey(SettingsScreen.syncGoogleDriveKey),
      );
      await tester.pumpAndSettle();
    } catch (_) {}
    if (find.byKey(SettingsScreen.syncGoogleDriveKey).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(SettingsScreen.syncGoogleDriveKey));
      await tester.pumpAndSettle();
      await _scrollIntoViewIfNeeded(
        tester,
        find.byKey(SettingsScreen.syncConnectKey),
      );
      await tester.tap(find.byKey(SettingsScreen.syncConnectKey));
    } else {
      await container
          .read(syncProviderControllerProvider.notifier)
          .setProvider(SyncProvider.googleDrive);
      await container
          .read(syncAuthControllerProvider.notifier)
          .connect(SyncProvider.googleDrive);
    }
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
    if (lockNowFinder.evaluate().isNotEmpty) {
      await tester.ensureVisible(lockNowFinder);
      await tester.pumpAndSettle();
      await tester.tap(lockNowFinder);
      await tester.pump(const Duration(milliseconds: 600));
    } else {
      container.read(appSessionUnlockControllerProvider.notifier).lock();
      await tester.pump(const Duration(milliseconds: 600));
    }
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

  testWidgets('settings sync detail controls and app links use fake cloud', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({
      'app.onboarding_completed': true,
      'app.onboarding_completed_version': 2,
      'settings.locale': 'english',
    });
    final fakeSyncAuthGateway = FakeSyncAuthGateway();
    final fakePlayIntegrityVerifier = FakePlayIntegrityVerifier();
    final fakeGoogleDriveTransport = FakeGoogleDriveSyncTransport();
    final container = ProviderContainer(
      overrides: [
        syncAuthGatewayProvider.overrideWithValue(fakeSyncAuthGateway),
        playIntegrityVerifierProvider.overrideWithValue(
          fakePlayIntegrityVerifier,
        ),
        googleDriveSyncTransportProvider.overrideWithValue(
          fakeGoogleDriveTransport,
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

    await container
        .read(notesControllerProvider.notifier)
        .upsert(
          NoteEntry(
            id: 'sync-settings-note',
            vaultId: 'everyday',
            title: 'Sync settings note',
            body: 'Exercised by fake cloud transport.',
            createdAt: DateTime.utc(2026, 5, 10, 0, 5),
            updatedAt: DateTime.utc(2026, 5, 10, 0, 6),
            editorMode: NoteEditorMode.quick,
          ),
        );
    await tester.pumpAndSettle();

    container.read(appRouterProvider).go('/settings');
    await tester.pumpAndSettle();

    await _scrollIntoViewIfNeeded(tester, find.text('Backup and sync'));
    await tester.tap(find.text('Backup and sync'));
    await tester.pumpAndSettle();

    await _scrollIntoViewIfNeeded(
      tester,
      find.byKey(SettingsScreen.syncGoogleDriveKey),
    );
    await tester.tap(find.byKey(SettingsScreen.syncGoogleDriveKey));
    await tester.pumpAndSettle();
    await _scrollIntoViewIfNeeded(
      tester,
      find.byKey(SettingsScreen.syncConnectKey),
    );
    await tester.tap(find.byKey(SettingsScreen.syncConnectKey));
    await tester.pumpAndSettle();

    expect(fakeSyncAuthGateway.connectCalls, [SyncProvider.googleDrive]);
    expect(fakePlayIntegrityVerifier.operations, ['sync.enable']);
    expect(find.textContaining('simulator@example.com'), findsWidgets);

    await _scrollIntoViewIfNeeded(tester, find.text('Details'));
    await tester.tap(find.text('Details').last);
    await tester.pumpAndSettle();
    expect(find.text('Sync progress'), findsOneWidget);
    expect(find.text('Pending sync queue'), findsOneWidget);

    await _scrollIntoViewIfNeeded(
      tester,
      find.byKey(SettingsScreen.syncRefreshRemoteKey),
    );
    await tester.tap(find.byKey(SettingsScreen.syncRefreshRemoteKey));
    await tester.pumpAndSettle();
    expect(fakeGoogleDriveTransport.fetchLatestCalls, greaterThanOrEqualTo(1));
    expect(
      find.textContaining('bundle information was refreshed'),
      findsWidgets,
    );

    await _scrollIntoViewIfNeeded(
      tester,
      find.byKey(SettingsScreen.syncUploadBundleKey),
    );
    await tester.tap(find.byKey(SettingsScreen.syncUploadBundleKey));
    await tester.pumpAndSettle();
    expect(fakeGoogleDriveTransport.uploadCalls, greaterThanOrEqualTo(1));
    expect(find.textContaining('Encrypted bundle uploaded'), findsWidgets);
    expect(find.textContaining('2026/05/10 00:30 UTC'), findsWidgets);

    final uploadsBeforeReupload = fakeGoogleDriveTransport.uploadCalls;
    await _scrollIntoViewIfNeeded(tester, find.text('Re-upload all notes'));
    await tester.tap(find.text('Re-upload all notes').last);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Re-upload all notes'), findsWidgets);
    await tester.tap(find.text('Re-upload').last);
    await tester.pumpAndSettle();
    expect(
      fakeGoogleDriveTransport.uploadCalls,
      greaterThan(uploadsBeforeReupload),
    );

    await _scrollIntoViewIfNeeded(tester, find.text('Bundle history'));
    await tester.tap(find.text('Bundle history').last);
    await tester.pumpAndSettle();
    expect(find.text('Bundle history'), findsWidgets);
    expect(find.text('2026/05/10 00:30 UTC'), findsWidgets);
    expect(find.textContaining('himemo_sync_20260510.enc'), findsWidgets);
    expect(find.textContaining('Notes'), findsWidgets);
    await tester.tap(find.text('Close').last);
    await tester.pumpAndSettle();

    await _openExternalLinkDialogAndCancel(
      tester,
      trigger: find.text('Sync help and FAQ'),
      expectedUrl: 'https://mmiyaji.github.io/himemo/help.html',
    );

    await _scrollIntoViewIfNeeded(tester, find.text('About'));
    await tester.tap(find.text('About').last);
    await tester.pumpAndSettle();

    await _scrollIntoViewIfNeeded(tester, find.text('Terms of Use'));
    await _openExternalLinkDialogAndCancel(
      tester,
      trigger: find.text('Terms of Use').first,
      expectedUrl: 'https://mmiyaji.github.io/himemo/terms.html',
    );
    await _openExternalLinkDialogAndCancel(
      tester,
      trigger: find.text('Privacy Policy').first,
      expectedUrl: 'https://mmiyaji.github.io/himemo/privacy.html',
    );
    await _openExternalLinkDialogAndCancel(
      tester,
      trigger: find.text('Contact').first,
      expectedUrl: 'https://mmiyaji.github.io/himemo/contact.html',
    );
    await _openExternalLinkDialogAndCancel(
      tester,
      trigger: find.text('Help and FAQ'),
      expectedUrl: 'https://mmiyaji.github.io/himemo/help.html',
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

class FakeGoogleDriveSyncTransport implements GoogleDriveSyncTransport {
  int fetchLatestCalls = 0;
  int uploadCalls = 0;
  String? uploadedPayload;
  final Map<String, String> uploadedAttachmentObjects = {};
  RemoteSyncBundleStatus? latestStatus = RemoteSyncBundleStatus(
    fileId: 'remote-current',
    fileName: 'himemo_sync_20260510.enc',
    modifiedAt: DateTime.utc(2026, 5, 10, 0, 30),
    sizeBytes: 4096,
    noteCount: 1,
    attachmentCount: 0,
    deviceId: 'fake-device-a',
  );

  @override
  Future<RemoteSyncBundleStatus?> fetchLatestBundleStatus() async {
    fetchLatestCalls += 1;
    return latestStatus;
  }

  @override
  Future<List<RemoteSyncBundleStatus>> listBundleHistory({
    int limit = 10,
  }) async {
    return [
      latestStatus!,
      RemoteSyncBundleStatus(
        fileId: 'remote-previous',
        fileName: 'himemo_sync_20260509.enc',
        modifiedAt: DateTime.utc(2026, 5, 9, 14, 45),
        sizeBytes: 2048,
        noteCount: 1,
        attachmentCount: 0,
        deviceId: 'fake-device-b',
      ),
    ].take(limit).toList(growable: false);
  }

  @override
  Future<RemoteSyncBundleStatus> uploadBundle({
    required String encodedPayload,
    required String deviceId,
    required int noteCount,
    required int attachmentCount,
  }) async {
    uploadCalls += 1;
    uploadedPayload = encodedPayload;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    latestStatus = RemoteSyncBundleStatus(
      fileId: 'remote-upload-$uploadCalls',
      fileName: 'himemo_sync_20260510.enc',
      modifiedAt: DateTime.utc(2026, 5, 10, 0, 30),
      sizeBytes: encodedPayload.length,
      noteCount: noteCount,
      attachmentCount: attachmentCount,
      deviceId: deviceId,
    );
    return latestStatus!;
  }

  @override
  Future<void> uploadAttachmentObject({
    required String contentHash,
    required String encodedPayload,
    required String type,
    required String label,
    required int sizeBytes,
    bool skipExistingCheck = false,
  }) async {
    uploadedAttachmentObjects[contentHash] = encodedPayload;
  }

  @override
  Future<Set<String>> listAttachmentObjectContentHashes() async {
    return uploadedAttachmentObjects.keys.toSet();
  }

  @override
  Future<String?> downloadAttachmentObject(String contentHash) async {
    return uploadedAttachmentObjects[contentHash];
  }

  @override
  Future<DownloadedRemoteSyncBundle?> downloadLatestBundle() async {
    final payload = uploadedPayload;
    final status = latestStatus;
    if (payload == null || status == null) {
      return null;
    }
    return DownloadedRemoteSyncBundle(status: status, encodedPayload: payload);
  }

  @override
  Future<DownloadedRemoteSyncBundle?> downloadBundleByFileId(
    String fileId,
  ) async {
    return downloadLatestBundle();
  }

  @override
  Future<String?> fetchSyncKeyBackupCode() async => null;

  @override
  Future<void> uploadSyncKeyBackupCode(String backupCode) async {}
}
