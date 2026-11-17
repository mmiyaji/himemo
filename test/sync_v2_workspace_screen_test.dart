import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';

import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/sync/data/sync_v2_history.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:himemo/features/home/presentation/home_page.dart';
import 'package:himemo/features/home/presentation/home_providers.dart'
    show NotesListDensity, NotesListSortField;
import 'package:himemo/features/sync/presentation/sync_v2_attachment_image.dart';
import 'package:himemo/l10n/app_strings.dart';
import 'package:himemo/features/sync/data/sync_v2_enrollment_store.dart';
import 'package:himemo/features/sync/data/sync_v2_generation_registration.dart';
import 'package:himemo/features/sync/data/sync_v2_inbox.dart';
import 'package:himemo/features/sync/data/sync_v2_note_repository.dart';
import 'package:himemo/features/sync/presentation/sync_v2_workspace.dart';
import 'package:himemo/features/sync/presentation/sync_v2_pairing_dialogs.dart';
import 'package:himemo/features/sync/presentation/sync_v2_workspace_screen.dart';
import 'package:himemo/features/sync/presentation/sync_v2_privacy.dart';
import 'package:himemo/features/sync/presentation/sync_v2_attachment_viewer.dart';
import 'package:himemo/features/sync/presentation/sync_v2_insights_view.dart';
import 'package:himemo/features/sync/presentation/sync_v2_rich_blocks_editor.dart';
import 'package:himemo/features/sync/presentation/sync_v2_responsive_navigation.dart';

String _syncPairingCode() => base64Url.encode(
  utf8.encode(
    jsonEncode({
      'format': 'himemo.sync.v2.recovery',
      'version': 1,
      'account': 'test-account',
      'generation': 'a' * 32,
      'key': base64Url.encode(List.filled(32, 7)),
    }),
  ),
);

String _adminPairingCode() =>
    'himemo-admin-v2:${base64.encode(utf8.encode(jsonEncode({'generation': 'a' * 32, 'key': base64.encode(List.filled(32, 9))})))}';

Widget _scannerDialog(String? result) => Builder(
  builder: (context) => AlertDialog(
    title: const Text('Fake scanner'),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(result),
        child: const Text('Return scanned code'),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel scan'),
      ),
    ],
  ),
);

class _PendingScanner extends StatefulWidget {
  const _PendingScanner(this.result);
  final Completer<String?> result;

  @override
  State<_PendingScanner> createState() => _PendingScannerState();
}

class _PendingScannerState extends State<_PendingScanner> {
  @override
  void initState() {
    super.initState();
    widget.result.future.then((code) {
      if (mounted && code != null) Navigator.of(context).pop(code);
    });
  }

  @override
  Widget build(BuildContext context) =>
      const AlertDialog(title: Text('Pending fake scanner'));
}

final class _PickedArchive extends PlatformFile {
  @override
  String get name => 'backup.zip';
  @override
  Uri get uri => Uri.parse('memory:backup.zip');
  @override
  Future<Uint8List> readAsBytes() async => Uint8List.fromList([1]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _DelayedPickedAttachment extends PlatformFile {
  _DelayedPickedAttachment(this.bytes);
  final Completer<Uint8List> bytes;
  final Completer<void> readStarted = Completer<void>();
  @override
  String get name => 'late-private.txt';
  @override
  Uri get uri => Uri.parse('memory:late-private.txt');
  @override
  Future<int?> length() async => 3;
  @override
  Future<Uint8List> readAsBytes() {
    if (!readStarted.isCompleted) readStarted.complete();
    return bytes.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ArchivePicker extends FilePickerPlatform {
  _ArchivePicker({this.onPickerCalled, this.files});

  final Future<void> Function()? onPickerCalled;
  final List<PlatformFile>? files;
  int calls = 0;

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    calls++;
    await onPickerCalled?.call();
    return files ?? [_PickedArchive()];
  }
}

class _Inbox implements SyncV2Inbox {
  @override
  Future<void> close() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Repository implements SyncV2NoteRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Cloud implements SyncV2GenerationRegistrationTransport {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Controller extends SyncV2WorkspaceController {
  _Controller({bool settingsAdminActive = false})
    : settingsAdminActiveForTest = settingsAdminActive,
      super(
        inbox: _Inbox(),
        repository: _Repository(),
        store: MemorySecureKeyValueStore(),
        enrollments: SyncV2EnrollmentStore(MemorySecureKeyValueStore()),
        registrationTransport: _Cloud(),
        registrationFactory: (_) => throw UnimplementedError(),
        syncOperation: () => throw UnimplementedError(),
        activate: () async {},
        deactivate: () async {},
        supported: true,
        settingsAdminAuthenticated: () => settingsAdminActive,
        automaticSync: false,
      );
  final bool settingsAdminActiveForTest;
  @override
  bool get settingsAdminActive => settingsAdminActiveForTest;
  bool settingsUnlockSucceeds = true;
  int settingsUnlockCalls = 0;
  int biometricUnlockCalls = 0;
  Uint8List previewBytes = Uint8List.fromList([1, 2, 3]);
  Completer<Uint8List>? previewBytesCompleter;
  Completer<void>? previewReadStarted;
  bool Function()? latestPreviewIsActive;
  Uint8List? latestPreviewBytes;
  final previewReads = <SyncV2AttachmentReference>[];
  @override
  Future<Uint8List> readAttachmentPreview(
    SyncV2AttachmentReference reference, {
    bool Function()? isActive,
  }) {
    previewReads.add(reference);
    latestPreviewIsActive = isActive;
    if (previewReadStarted != null && !previewReadStarted!.isCompleted) {
      previewReadStarted!.complete();
    }
    final pending = previewBytesCompleter;
    if (pending != null) {
      return pending.future.then((bytes) {
        latestPreviewBytes = bytes;
        return bytes;
      });
    }
    latestPreviewBytes = Uint8List.fromList(previewBytes);
    return Future.value(latestPreviewBytes);
  }

  @override
  Future<bool> unlockAdminFromSettings() async {
    settingsUnlockCalls++;
    if (!settingsUnlockSucceeds) return false;
    isAdmin = true;
    notifyListeners();
    return true;
  }

  bool biometricSetup = false;
  Future<void> Function()? biometricDelay;
  @override
  bool get preparedUsesBiometrics => biometricSetup;
  @override
  Future<({String syncCode, String adminCode})> prepareNewBiometric() async {
    biometricAuthenticating = true;
    await biometricDelay?.call();
    biometricAuthenticating = false;
    biometricSetup = true;
    prepared = true;
    notifyListeners();
    return (syncCode: 'SYNC-secret-code', adminCode: 'ADMIN-secret-code');
  }

  int confirmations = 0;
  int cancellations = 0;
  bool prepared = false;
  final passwords = <String>[];
  @override
  bool get hasPreparedSetup => prepared;
  String? chosenVersion;
  SyncV2WorkspaceNote? savedOriginal;
  List<String>? savedTags;
  List<NoteBlock>? savedBlocks;
  List<String>? savedRemovedAttachmentIds;
  List<SyncV2PendingAttachment>? savedAddedFiles;
  bool? savedPinned;
  bool? savedArchived;
  String? managedTag;
  String? renamedTag;
  @override
  Future<void> updateTag(String source, {String? replacement}) async {
    managedTag = source;
    renamedTag = replacement;
  }

  @override
  Future<void> setNoteArchived(
    SyncV2WorkspaceNote note, {
    required bool archived,
  }) async {
    savedArchived = archived;
    notes = [
      for (final entry in notes)
        if (entry.note.id == note.note.id)
          SyncV2WorkspaceNote(
            entry.note.copyWith(archivedAt: archived ? DateTime.now() : null),
            entry.snapshot,
            entry.attachments,
          )
        else
          entry,
    ];
    notifyListeners();
  }

  @override
  Future<void> saveNote({
    SyncV2WorkspaceNote? original,
    String? selectedVersionId,
    required String title,
    required String body,
    List<NoteBlock>? blocks,
    bool? isPinned,
    List<String>? tags,
    List<SyncV2PendingAttachment> addedFiles = const [],
    List<String> removedAttachmentIds = const [],
  }) async {
    chosenVersion = selectedVersionId;
    savedOriginal = original;
    savedTags = tags;
    savedBlocks = blocks;
    savedAddedFiles = List.of(addedFiles);
    savedPinned = isPinned;
    savedRemovedAttachmentIds = List.of(removedAttachmentIds);
  }

  final availablePrivateProfiles = <SyncV2WorkspaceProfile>[];
  bool isAdmin = false;
  Future<void> Function()? importBiometricDelay;
  Map<String, String>? importedDestinations;
  String? inspectedArchivePassword;
  bool? importedAdminOverwrite;
  bool? importedAcceptUnlinked;
  bool failAdminUnlock = false;
  final adminPasswords = <String>[];
  final recoveryCodes = <String>[];
  final adminRecoveryCodes = <String>[];
  final pairingEvents = <String>[];
  int recoveryCodeDisplayCalls = 0;
  @override
  Future<void> recover(String code) async {
    recoveryCodes.add(code);
    pairingEvents.add('sync:$code');
    registered = true;
    notifyListeners();
  }

  @override
  Future<void> recoverAdminBiometric(String code) async {
    adminRecoveryCodes.add(code);
    pairingEvents.add('admin:$code');
    isAdmin = true;
    notifyListeners();
  }

  @override
  Future<({String syncCode, String? adminCode})> showRecoveryCodes() async {
    recoveryCodeDisplayCalls++;
    return (syncCode: _syncPairingCode(), adminCode: _adminPairingCode());
  }

  @override
  Future<SyncV2ArchiveInspection> inspectArchive(
    Uint8List bytes, {
    String? password,
  }) async {
    inspectedArchivePassword = password;
    return SyncV2ArchiveInspection({'everyday': 33, 'private': 20}, 0);
  }

  @override
  Future<void> importArchive({
    required Uint8List bytes,
    String? password,
    required Map<String, String> destinations,
    required bool acceptUnlinkedAttachments,
  }) async {
    importedDestinations = Map.of(destinations);
  }

  @override
  Future<void> adminImportArchive({
    required Uint8List bytes,
    String? password,
    SyncV2ArchiveInspection? inspection,
  }) async {
    importedAdminOverwrite = true;
    importedAcceptUnlinked = true;
  }

  @override
  Future<void> unlockAdmin(String password) async {
    adminPasswords.add(password);
    if (failAdminUnlock) throw StateError('incorrect password');
    isAdmin = true;
    notifyListeners();
  }

  @override
  Future<void> unlockAdminBiometric() async {
    biometricUnlockCalls++;
    biometricAuthenticating = true;
    await importBiometricDelay?.call();
    biometricAuthenticating = false;
    isAdmin = true;
    availablePrivateProfiles.add(
      const SyncV2WorkspaceProfile(
        'private_profile:existing',
        'Existing private',
      ),
    );
    notifyListeners();
  }

  @override
  bool get adminUnlocked => isAdmin;

  bool backgroundCalled = false;
  int backgroundCalls = 0;
  bool fakeDisposed = false;
  bool clearNotesOnBackground = false;
  @override
  void dispose() {
    fakeDisposed = true;
    super.dispose();
  }

  @override
  Future<void> initialize() async {
    loading = false;
    notifyListeners();
  }

  @override
  Future<({String syncCode, String adminCode})> prepareNew(
    String adminPassword,
  ) async {
    prepared = true;
    passwords.add(adminPassword);
    notifyListeners();
    return (syncCode: 'SYNC-secret-code', adminCode: 'ADMIN-secret-code');
  }

  @override
  Future<void> confirmSetup() async {
    confirmations++;
    registered = true;
    notifyListeners();
  }

  @override
  Future<void> cancelSetup() async {
    cancellations++;
    prepared = false;
    notifyListeners();
  }

  @override
  List<SyncV2WorkspaceProfile> get profiles => [
    const SyncV2WorkspaceProfile('normal', '通常', isNormal: true),
    ...availablePrivateProfiles,
  ];
  @override
  void background() {
    backgroundCalled = true;
    backgroundCalls++;
    availablePrivateProfiles.clear();
    isAdmin = false;
    if (clearNotesOnBackground) {
      notes = [];
      selectedProfileId = null;
    }
    if (!fakeDisposed) notifyListeners();
  }

  @override
  Future<void> resume() async {}
}

class _AttachmentViewer implements SyncV2AttachmentViewer {
  Completer<void>? openCompleter;
  Uint8List? openedBytes;
  String? openedLabel;
  int openCalls = 0;
  int closeCalls = 0;
  bool _openInProgress = false;

  @override
  Future<void> open({required Uint8List bytes, required String label}) async {
    openCalls++;
    openedBytes = bytes;
    openedLabel = label;
    _openInProgress = true;
    try {
      await openCompleter?.future;
    } finally {
      _openInProgress = false;
    }
  }

  @override
  Future<void> close() async {
    closeCalls++;
    if (_openInProgress &&
        openCompleter != null &&
        !openCompleter!.isCompleted) {
      openCompleter!.complete();
    }
  }
}

SyncV2AttachmentReference _attachmentReference({
  String type = 'photo',
  String label = 'photo.jpg',
}) => SyncV2AttachmentReference(
  id: 'a' * 64,
  label: label,
  type: type,
  size: 1,
  sha256: 'b' * 64,
  chunks: ['blob_${'c' * 64}'],
);

Uint8List _pixel() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADUlEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC',
);

SyncV2WorkspaceNote _note(
  String id, {
  required String title,
  required String body,
  required DateTime createdAt,
  DateTime? updatedAt,
  List<String> tags = const [],
  List<SyncV2AttachmentReference> attachments = const [],
  List<NoteBlock> blocks = const [],
  String profileId = 'normal',
  NoteEditorMode editorMode = NoteEditorMode.rich,
}) {
  final note = NoteEntry(
    id: id,
    vaultId: profileId,
    title: title,
    body: body,
    createdAt: createdAt,
    updatedAt: updatedAt,
    tags: tags,
    attachments: [
      for (final attachment in attachments)
        NoteAttachment(
          type: AttachmentType.values.byName(attachment.type),
          label: attachment.label,
          filePath: 'v2attachment:${attachment.id}',
        ),
    ],
    blocks: blocks,
    editorMode: editorMode,
  );
  return SyncV2WorkspaceNote(
    note,
    SyncV2NoteSnapshot(
      versions: [
        SyncV2NoteVersion(
          change: SyncV2Change(
            id: 'change-$id',
            profileId: profileId,
            noteId: id,
            operation: SyncV2Operation.upsert,
            parentIds: {},
            payloadDigest: 'digest-$id',
          ),
          payloadAvailable: true,
          body: {
            'type': 'note',
            'note': note.toJson(),
            'attachments': [
              for (final attachment in attachments) attachment.toJson(),
            ],
          },
        ),
      ],
      pendingIds: {},
    ),
    attachments,
  );
}

void main() {
  testWidgets(
    'workspace lifetime enables native privacy protection independently of legacy profiles',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        syncV2DisplayStylePreference: 'simple',
      });
      final controller = _Controller();
      final container = ProviderContainer(
        overrides: [syncV2WorkspaceProvider.overrideWithValue(controller)],
      );
      addTearDown(container.dispose);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SyncV2WorkspaceScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(container.read(syncV2PrivacyActiveProvider), isTrue);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SizedBox.shrink()),
        ),
      );
      await tester.pumpAndSettle();
      expect(container.read(syncV2PrivacyActiveProvider), isFalse);
      expect(controller.backgroundCalled, isTrue);
    },
  );
  Future<void> mount(
    WidgetTester tester,
    _Controller controller, {
    Widget Function(bool administrator)? scannerBuilder,
    SyncV2AttachmentViewer? attachmentViewer,
    String? displayStyle = 'simple',
    bool resetDisplayStyle = true,
    bool localOnly = false,
    bool cloudSandbox = false,
    GoRouter? router,
  }) async {
    if (resetDisplayStyle) {
      final initialPreferences = <String, Object>{};
      if (displayStyle != null) {
        initialPreferences[syncV2DisplayStylePreference] = displayStyle;
      }
      SharedPreferences.setMockInitialValues(initialPreferences);
    }
    const List<LocalizationsDelegate<dynamic>> delegates = [
      AppStrings.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ];
    final app = router == null
        ? MaterialApp(
            localizationsDelegates: delegates,
            supportedLocales: AppStrings.supportedLocales,
            home: SyncV2WorkspaceScreen(
              localOnly: localOnly,
              cloudSandbox: cloudSandbox,
            ),
          )
        : MaterialApp.router(
            localizationsDelegates: delegates,
            supportedLocales: AppStrings.supportedLocales,
            routerConfig: router,
          );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          syncV2WorkspaceProvider.overrideWithValue(controller),
          if (scannerBuilder != null)
            syncV2PairingScannerBuilderProvider.overrideWithValue(
              scannerBuilder,
            ),
          if (attachmentViewer != null)
            syncV2AttachmentViewerProvider.overrideWithValue(attachmentViewer),
        ],
        child: app,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openEditorFromList(
    WidgetTester tester,
    Finder note, {
    bool settlePreview = true,
  }) async {
    final previewList = find.byType(HomeNotePreviewList);
    final list = previewList.evaluate().isNotEmpty
        ? previewList
        : find.byType(ListView).first;
    final scrollable = previewList.evaluate().isNotEmpty
        ? find
              .descendant(of: previewList, matching: find.byType(Scrollable))
              .first
        : find.descendant(of: list, matching: find.byType(Scrollable)).first;
    await tester.ensureVisible(note);
    for (var attempt = 0; attempt < 4; attempt++) {
      if (tester.getRect(note).bottom <= tester.getRect(list).bottom - 8) break;
      await tester.drag(scrollable, const Offset(0, -120));
      await tester.pumpAndSettle();
    }
    await tester.tap(note);
    if (settlePreview) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
    await tester.tap(find.byTooltip('Edit'));
    if (settlePreview) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> selectDisplayStyle(
    WidgetTester tester,
    SyncV2DisplayStyle style,
  ) async {
    if (find
        .byKey(const ValueKey('sync-v2-display-style'))
        .evaluate()
        .isEmpty) {
      await tester.tap(find.byKey(const ValueKey('sync-v2-profile-actions')));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const ValueKey('sync-v2-display-style')));
    await tester.pumpAndSettle();
    final label = style == SyncV2DisplayStyle.original
        ? 'Original design'
        : 'Simple view';
    await tester.ensureVisible(find.text(label).last);
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('local preview does not offer remote sync or pairing', (
    tester,
  ) async {
    final controller = _Controller();
    addTearDown(controller.dispose);
    await mount(tester, controller, localOnly: true);
    expect(find.text('Set up local encrypted notes'), findsOneWidget);
    expect(find.byKey(const ValueKey('sync-v2-scan-join')), findsNothing);
    expect(find.byTooltip('Sync'), findsNothing);
    expect(find.text('Restore with recovery code (SYNC)'), findsOneWidget);

    controller
      ..registered = true
      ..selectedProfileId = 'normal'
      ..notifyListeners();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Sync'), findsNothing);
    expect(find.text('Open legacy data (leave v2 sync)'), findsNothing);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Show recovery codes'), findsOneWidget);
    expect(find.text('Add another device with QR'), findsNothing);
    expect(find.text('Show administrator QR'), findsNothing);
  });

  testWidgets('cloud sandbox allows sync but hides incompatible pairing', (
    tester,
  ) async {
    final controller = _Controller();
    addTearDown(controller.dispose);
    await mount(tester, controller, cloudSandbox: true);
    expect(find.text('CloudKit development sandbox'), findsOneWidget);
    expect(find.byKey(const ValueKey('sync-v2-scan-join')), findsNothing);
    expect(find.byTooltip('Sync'), findsOneWidget);
    controller
      ..registered = true
      ..selectedProfileId = 'normal'
      ..notifyListeners();
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Show recovery codes'), findsOneWidget);
    expect(find.text('Add another device with QR'), findsNothing);
    expect(find.text('Open legacy data (leave v2 sync)'), findsNothing);
  });

  testWidgets('registered workspace defaults to original HiMemo design', (
    tester,
  ) async {
    final c = _Controller()
      ..registered = true
      ..selectedProfileId = 'normal'
      ..notes = [
        _note(
          'default-note',
          title: 'Original note',
          body: 'Preview body',
          createdAt: DateTime.utc(2025),
        ),
      ];
    addTearDown(c.dispose);
    await mount(tester, c, displayStyle: null);
    expect(find.byType(HomeBrandTitle), findsOneWidget);
    expect(find.byType(HomeNotePreviewList), findsOneWidget);
    expect(find.byKey(const ValueKey('sync-v2-search')), findsOneWidget);
  });

  testWidgets(
    'original mobile header keeps profile actions and removes duplicate icons',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final c = _Controller()
        ..registered = true
        ..selectedProfileId = 'normal';
      addTearDown(c.dispose);
      await mount(tester, c, displayStyle: null);
      expect(find.text('HiMemo'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('sync-v2-profile-actions')),
        findsOneWidget,
      );
      for (final key in [
        'sync-v2-open-settings',
        'sync-v2-trash-toggle',
        'sync-v2-calendar-toggle',
        'sync-v2-insights-toggle',
        'sync-v2-density',
        'sync-v2-sort',
      ]) {
        expect(find.byKey(ValueKey(key)), findsNothing);
      }
      await tester.tap(find.byKey(const ValueKey('sync-v2-profile-actions')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Unlock private'), findsOneWidget);
      expect(find.byTooltip('Lock'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('sync-v2-profile-trash')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('sync-v2-display-style')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('mobile note swipes close preview and protect unsaved edits', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final c = _Controller()
      ..registered = true
      ..selectedProfileId = 'normal'
      ..notes = [
        _note(
          'swipe',
          title: 'Swipe note',
          body: 'Saved',
          createdAt: DateTime.now(),
        ),
      ];
    addTearDown(c.dispose);
    await mount(tester, c, displayStyle: null);
    await tester.tap(find.text('Swipe note'));
    await tester.pumpAndSettle();
    final region = find.byKey(const ValueKey('sync-v2-note-swipe-region'));
    final rect = tester.getRect(region);
    await tester.dragFrom(
      Offset(rect.right - 8, rect.center.dy),
      const Offset(-140, 0),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sync-v2-preview-back')), findsNothing);
    await tester.tap(find.text('Swipe note'));
    await tester.pumpAndSettle();
    final top = tester.getRect(region).topCenter;
    await tester.dragFrom(top + const Offset(0, 10), const Offset(0, 130));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sync-v2-preview-back')), findsNothing);
    await tester.tap(find.text('Swipe note'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('sync-v2-title')), 'Unsaved');
    await tester.pump();
    final editorTop = tester.getRect(region).topCenter;
    await tester.dragFrom(
      editorTop + const Offset(0, 10),
      const Offset(0, 130),
    );
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('sync-v2-title')))
          .controller!
          .text,
      'Unsaved',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('external profile lock closes the V2 search details dialog', (
    tester,
  ) async {
    final c = _Controller()
      ..registered = true
      ..selectedProfileId = 'normal'
      ..notes = [
        _note(
          'private-search',
          title: 'Private text',
          body: '',
          tags: ['private-tag'],
          createdAt: DateTime.now(),
        ),
      ];
    addTearDown(c.dispose);
    await mount(tester, c, displayStyle: null);
    await tester.tap(find.byKey(const ValueKey('sync-v2-search-filters')));
    await tester.pumpAndSettle();
    expect(find.text('#private-tag'), findsWidgets);
    c.lockPrivate();
    await tester.pumpAndSettle();
    expect(find.text('#private-tag'), findsNothing);
    expect(find.text('Density'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet keeps the scrollable note list beside the preview', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final c = _Controller()
      ..registered = true
      ..selectedProfileId = 'normal'
      ..notes = [
        for (var i = 0; i < 15; i++)
          _note(
            'tablet-$i',
            title: 'Tablet note $i',
            body: 'Preview body $i',
            createdAt: DateTime(2025, 1, 30).subtract(Duration(days: i)),
          ),
      ];
    addTearDown(c.dispose);
    await mount(tester, c, displayStyle: null);
    final list = find.byType(HomeNotePreviewList);
    expect(list, findsOneWidget);
    await tester.tap(find.text('Tablet note 0'));
    await tester.pumpAndSettle();
    expect(find.text('Preview body 0'), findsWidgets);
    expect(list, findsOneWidget);
    expect(find.byKey(const ValueKey('sync-v2-preview-back')), findsNothing);
    final searchSection = find.ancestor(
      of: find.byKey(const ValueKey('sync-v2-search')),
      matching: find.byType(HomeNoteSection),
    );
    final previewPadding = find.byKey(
      const ValueKey('sync-v2-wide-preview-pane'),
    );
    expect(
      tester.getTopLeft(searchSection).dy,
      tester.getTopLeft(previewPadding).dy + 12,
    );
    await tester.drag(list, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('Tablet note 0'), findsOneWidget);
    expect(find.text('Preview body 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide navigation switches sections and reaches settings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final c = _Controller()
      ..notes = [
        _note(
          'nav-note',
          title: 'Navigation note',
          body: 'body',
          createdAt: DateTime.now(),
          tags: ['Work'],
        ),
      ];
    addTearDown(c.dispose);
    final router = GoRouter(
      initialLocation: '/sync-v2',
      routes: [
        GoRoute(
          path: '/sync-v2',
          builder: (context, state) => const SyncV2WorkspaceScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const Scaffold(
            body: Center(child: Text('Settings route reached')),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await mount(tester, c, displayStyle: null, router: router);

    expect(find.byType(SyncV2ResponsiveNavigation), findsNothing);
    c
      ..registered = true
      ..selectedProfileId = 'normal'
      ..notifyListeners();
    await tester.pumpAndSettle();
    final navigation = find.byType(SyncV2ResponsiveNavigation);
    expect(navigation, findsOneWidget);
    expect(
      MediaQuery.sizeOf(tester.element(find.byType(SyncV2WorkspaceScreen)))
          .width,
      greaterThanOrEqualTo(840),
    );
    expect(tester.widget<SyncV2ResponsiveNavigation>(navigation).wide, isTrue);
    for (final label in [
      'Notes',
      'Calendar',
      'Insights',
      'Trash',
      'Manage tags',
      'Settings',
    ]) {
      expect(
        find.descendant(of: navigation, matching: find.text(label)),
        findsOneWidget,
      );
    }

    await tester.tap(
      find.descendant(of: navigation, matching: find.text('Calendar')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sync-v2-calendar')), findsOneWidget);
    await tester.tap(
      find.descendant(of: navigation, matching: find.text('Insights')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SyncV2InsightsView), findsOneWidget);
    await tester.tap(
      find.descendant(of: navigation, matching: find.text('Trash')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sync-v2-trash')), findsOneWidget);
    await tester.tap(
      find.descendant(of: navigation, matching: find.text('Manage tags')),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: navigation, matching: find.text('Manage tags')),
      findsOneWidget,
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: navigation, matching: find.text('Settings')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Settings route reached'), findsOneWidget);
  });

  testWidgets(
    'wide original view moves profile controls to app bar and list options to details',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final c = _Controller()
        ..registered = true
        ..selectedProfileId = 'normal';
      addTearDown(c.dispose);
      await mount(tester, c, displayStyle: null);
      expect(
        find.byKey(const ValueKey('sync-v2-archive-toggle')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('sync-v2-sort')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('sync-v2-profile-actions')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('sync-v2-archive-toggle')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('sync-v2-sort')), findsNothing);
      expect(
        find.byKey(const ValueKey('sync-v2-display-style')),
        findsOneWidget,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sync-v2-search-filters')));
      await tester.pumpAndSettle();
      expect(find.text('Density'), findsOneWidget);
      expect(find.text('Sort by'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sync-v2-profile-actions')));
      await tester.pumpAndSettle();
      c.lockPrivate();
      await tester.pumpAndSettle();
      expect(find.text('Profile and sync'), findsNothing);
    },
  );

  testWidgets('shared V1 sidebar filters only visible V2 profile tags', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final c = _Controller()
      ..registered = true
      ..selectedProfileId = 'normal'
      ..notes = [
        _note(
          'tagged',
          title: 'V2 tagged',
          body: '',
          tags: ['Work'],
          createdAt: DateTime.now(),
        ),
        _note('other', title: 'V2 other', body: '', createdAt: DateTime.now()),
        _note(
          'private',
          title: 'Private content',
          body: '',
          tags: ['Private secret'],
          profileId: 'private',
          createdAt: DateTime.now(),
        ),
      ];
    addTearDown(c.dispose);
    await mount(tester, c, displayStyle: null);
    final nav = find.byType(SyncV2ResponsiveNavigation);
    expect(
      find.descendant(of: nav, matching: find.text('Work')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: nav, matching: find.text('Private secret')),
      findsNothing,
    );
    await tester.tap(find.descendant(of: nav, matching: find.text('Work')));
    await tester.pumpAndSettle();
    expect(find.text('V2 tagged'), findsOneWidget);
    expect(find.text('V2 other'), findsNothing);
    await tester.tap(
      find.descendant(of: nav, matching: find.text('All notes')),
    );
    await tester.pumpAndSettle();
    expect(find.text('V2 other'), findsOneWidget);
  });

  testWidgets(
    'mobile navigation is shown after registration and changes views',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final c = _Controller()
        ..notes = [
          _note(
            'mobile-nav-note',
            title: 'Mobile navigation note',
            body: 'body',
            createdAt: DateTime.now(),
            tags: ['Work'],
          ),
        ];
      addTearDown(c.dispose);
      await mount(tester, c, displayStyle: null);

      expect(find.byType(SyncV2ResponsiveNavigation), findsNothing);
      c
        ..registered = true
        ..selectedProfileId = 'normal'
        ..notifyListeners();
      await tester.pumpAndSettle();
      final navigation = find.byType(SyncV2ResponsiveNavigation);
      expect(navigation, findsOneWidget);
      expect(
        tester.widget<SyncV2ResponsiveNavigation>(navigation).wide,
        isFalse,
      );
      for (final label in ['Notes', 'Calendar', 'Insights', 'Settings']) {
        expect(
          find.descendant(of: navigation, matching: find.text(label)),
          findsOneWidget,
        );
      }
      await tester.tap(
        find.descendant(of: navigation, matching: find.text('Calendar')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sync-v2-calendar')), findsOneWidget);
      await tester.tap(
        find.descendant(of: navigation, matching: find.text('Insights')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SyncV2InsightsView), findsOneWidget);
      await tester.tap(
        find.descendant(of: navigation, matching: find.text('Notes')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sync-v2-search')), findsOneWidget);
    },
  );

  testWidgets(
    'blocked navigation preserves drafts and profile lock clears them',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final c = _Controller()
        ..registered = true
        ..selectedProfileId = 'normal'
        ..notes = [
          _note(
            'draft-nav-note',
            title: 'Draft source',
            body: 'saved body',
            createdAt: DateTime.now(),
          ),
        ];
      addTearDown(c.dispose);
      await mount(tester, c, displayStyle: null);
      await tester.ensureVisible(find.text('Draft source'));
      await openEditorFromList(tester, find.text('Draft source'));
      final title = find.byKey(const Key('sync-v2-title'));
      await tester.enterText(title, 'Unsaved navigation draft');

      final navigation = find.byType(SyncV2ResponsiveNavigation);
      expect(navigation, findsOneWidget);
      await tester.tap(
        find.descendant(of: navigation, matching: find.text('Calendar')),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(title).controller!.text,
        'Unsaved navigation draft',
      );
      expect(find.byKey(const ValueKey('sync-v2-calendar')), findsNothing);

      c
        ..busy = true
        ..notifyListeners();
      await tester.pump();
      await tester.tap(
        find.descendant(of: navigation, matching: find.text('Trash')),
      );
      await tester.pump();
      expect(
        tester.widget<TextField>(title).controller!.text,
        'Unsaved navigation draft',
      );
      expect(find.byKey(const ValueKey('sync-v2-trash')), findsNothing);

      c
        ..busy = false
        ..notifyListeners();
      await tester.pump();
      c.lockPrivate();
      await tester.pumpAndSettle();
      expect(find.text('Unsaved navigation draft'), findsNothing);
      expect(find.text('Draft source'), findsNothing);
    },
  );

  testWidgets('unavailable notes redact cached text and attachment metadata', (
    tester,
  ) async {
    final attachment = _attachmentReference(label: 'SECRET attachment label');
    final cached = _note(
      'unavailable-secret',
      title: 'SECRET cached title',
      body: 'SECRET cached body',
      createdAt: DateTime.now(),
      tags: ['SECRET tag'],
      attachments: [attachment],
    );
    final version = cached.versions.single;
    final unavailable = SyncV2WorkspaceNote(
      cached.note,
      SyncV2NoteSnapshot(
        versions: [
          SyncV2NoteVersion(
            change: version.change,
            payloadAvailable: false,
            body: null,
          ),
        ],
        pendingIds: {'pending'},
      ),
      [attachment],
    );
    final c = _Controller()
      ..registered = true
      ..selectedProfileId = 'normal'
      ..notes = [unavailable];
    addTearDown(c.dispose);
    await mount(tester, c, displayStyle: null);

    for (final secret in [
      'SECRET cached title',
      'SECRET cached body',
      'SECRET attachment label',
      'SECRET tag',
    ]) {
      expect(find.text(secret), findsNothing);
    }
    expect(find.byType(SyncV2AttachmentImage), findsNothing);
    expect(c.previewReads, isEmpty);

    final tile = find.byKey(const ValueKey('note-tile-unavailable-secret'));
    final listScroll = find
        .descendant(
          of: find.byType(HomeNotePreviewList),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.drag(listScroll, const Offset(0, -240));
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.text('Missing or locked · read only'), findsWidgets);
    for (final secret in [
      'SECRET cached title',
      'SECRET cached body',
      'SECRET attachment label',
    ]) {
      expect(find.text(secret), findsNothing);
    }
    expect(find.byTooltip('Edit'), findsNothing);
    expect(find.byType(SyncV2AttachmentImage), findsNothing);
    expect(c.previewReads, isEmpty);
  });

  testWidgets('advanced search filters V2 notes and clears on lock', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final first = _note(
      'first',
      title: 'Pinned work',
      body: 'body',
      tags: ['Work', 'Plan'],
      createdAt: DateTime.now(),
    );
    final pinned = SyncV2WorkspaceNote(
      first.note.copyWith(isPinned: true),
      first.snapshot,
      first.attachments,
    );
    final c = _Controller()
      ..registered = true
      ..selectedProfileId = 'normal'
      ..notes = [
        pinned,
        _note(
          'second',
          title: 'Other work',
          body: 'body',
          tags: ['Work'],
          createdAt: DateTime.now(),
        ),
      ];
    addTearDown(c.dispose);
    await mount(tester, c, displayStyle: null);
    await tester.tap(find.byKey(const ValueKey('sync-v2-search-filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pinned only'));
    await tester.tap(find.text('#Plan').last);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('Pinned work'), findsOneWidget);
    expect(find.text('Other work'), findsNothing);
    expect(find.byKey(const ValueKey('sync-v2-filter-count')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sync-v2-search-filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset'));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('Other work'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sync-v2-search-filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pinned only'));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(find.text('Pinned only'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
  });

  testWidgets(
    'advanced search fits a narrow screen and reset restores date range',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final c = _Controller()
        ..registered = true
        ..selectedProfileId = 'normal';
      addTearDown(c.dispose);
      await mount(tester, c, displayStyle: null);
      await tester.tap(find.byKey(const ValueKey('sync-v2-search-filters')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('All dates'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All dates'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Last 7 days').last);
      await tester.pumpAndSettle();
      expect(find.text('Last 7 days'), findsOneWidget);
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      expect(find.text('All dates'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'automatic tag rule can be created and applies to saved V2 notes',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final c = _Controller()
        ..registered = true
        ..selectedProfileId = 'normal'
        ..notes = [
          _note(
            'invoice',
            title: 'Invoice to pay',
            body: 'Details',
            createdAt: DateTime.now(),
          ),
        ];
      addTearDown(c.dispose);
      await mount(tester, c, displayStyle: null);
      await tester.tap(
        find.descendant(
          of: find.byType(SyncV2ResponsiveNavigation),
          matching: find.text('Manage tags'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sync-v2-auto-tag-manage')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add rule'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('sync-v2-auto-tag-name')),
        'Finance',
      );
      await tester.enterText(
        find.byKey(const ValueKey('sync-v2-auto-tag-keywords')),
        'Invoice',
      );
      await tester.tap(find.byKey(const ValueKey('sync-v2-auto-tag-save')));
      await tester.pumpAndSettle();
      expect(find.text('Finance'), findsOneWidget);
      await tester.tap(find.text('Apply to V2 notes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm and continue'));
      await tester.pumpAndSettle();
      expect(c.savedTags, contains('Finance'));
      expect(c.savedOriginal?.note.id, 'invoice');
      await tester.tap(find.text('Close').last);
      await tester.pumpAndSettle();
      await openEditorFromList(tester, find.text('Invoice to pay'));
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(c.savedTags, contains('Finance'));
    },
  );

  testWidgets(
    'archive, trash and calendar hide unavailable or conflicting content',
    (tester) async {
      final now = DateTime.now();
      SyncV2WorkspaceNote unavailable(String id, {bool archived = false}) {
        final cached = _note(
          id,
          title: 'SECRET $id',
          body: 'SECRET body $id',
          createdAt: now,
        );
        final version = cached.versions.single;
        return SyncV2WorkspaceNote(
          cached.note.copyWith(
            archivedAt: archived ? now : null,
            deletedAt: archived ? null : now,
          ),
          SyncV2NoteSnapshot(
            versions: [
              SyncV2NoteVersion(
                change: version.change,
                payloadAvailable: false,
                body: null,
              ),
            ],
            pendingIds: {'pending'},
          ),
          [],
        );
      }

      final cached = _note(
        'conflicting',
        title: 'SECRET conflict',
        body: 'SECRET conflict body',
        createdAt: now,
      );
      final conflict = SyncV2WorkspaceNote(
        cached.note,
        SyncV2NoteSnapshot(
          versions: [
            cached.versions.single,
            SyncV2NoteVersion(
              change: SyncV2Change(
                id: 'other',
                profileId: 'normal',
                noteId: 'conflicting',
                operation: SyncV2Operation.upsert,
                parentIds: {},
                payloadDigest: 'other',
              ),
              payloadAvailable: true,
              body: cached.versions.single.body,
            ),
          ],
          pendingIds: {},
        ),
        [],
      );
      final c = _Controller()
        ..registered = true
        ..selectedProfileId = 'normal'
        ..notes = [
          unavailable('archived', archived: true),
          unavailable('deleted'),
          conflict,
        ];
      addTearDown(c.dispose);
      await mount(tester, c);

      await tester.tap(find.byKey(const ValueKey('sync-v2-archive-toggle')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('sync-v2-archive-note-archived')),
        findsOneWidget,
      );
      expect(find.text('SECRET archived'), findsNothing);
      expect(find.text('SECRET body archived'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('sync-v2-trash-toggle')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('sync-v2-trash-note-deleted')),
        findsOneWidget,
      );
      expect(find.text('SECRET deleted'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('sync-v2-calendar-toggle')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('sync-v2-calendar-note-conflicting')),
        findsNothing,
      );
      expect(find.text('SECRET conflict'), findsNothing);
      expect(find.text('SECRET conflict body'), findsNothing);
    },
  );

  testWidgets('insights switch and profile changes discard prior aggregates', (
    tester,
  ) async {
    final now = DateTime.now();
    final c = _Controller()
      ..registered = true
      ..selectedProfileId = 'normal'
      ..notes = [
        _note(
          'normal-activity',
          title: 'Normal note',
          body: 'normal content',
          createdAt: now,
        ),
      ];
    c.availablePrivateProfiles.add(
      const SyncV2WorkspaceProfile('private', 'Private'),
    );
    addTearDown(c.dispose);
    await mount(tester, c);

    await tester.tap(find.byKey(const ValueKey('sync-v2-insights-toggle')));
    await tester.pumpAndSettle();
    expect(find.byType(SyncV2InsightsView), findsOneWidget);

    c.selectedProfileId = 'private';
    c.notes = [
      _note(
        'private-one',
        title: 'Private one',
        body: 'one',
        createdAt: now,
        profileId: 'private',
      ),
      _note(
        'private-two',
        title: 'Private two',
        body: 'two',
        createdAt: now,
        profileId: 'private',
      ),
    ];
    c.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.byType(SyncV2InsightsView), findsNothing);

    await tester.tap(find.byKey(const ValueKey('sync-v2-insights-toggle')));
    await tester.pumpAndSettle();
    expect(find.byType(SyncV2InsightsView), findsOneWidget);

    c.selectedProfileId = null;
    c.notes = [];
    c.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.byType(SyncV2InsightsView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'calendar shows only selected profile ready notes and preserves drafts',
    (tester) async {
      final now = DateTime.now();
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final unavailable = _note(
        'unavailable',
        title: 'Unavailable secret',
        body: 'hidden',
        createdAt: now,
      );
      final deleted = _note(
        'deleted',
        title: 'Deleted secret',
        body: 'hidden',
        createdAt: now,
      );
      final c = _Controller()
        ..registered = true
        ..selectedProfileId = 'normal'
        ..notes = [
          _note(
            'today',
            title: 'Calendar visible note',
            body: 'Calendar body',
            createdAt: now,
          ),
          SyncV2WorkspaceNote(
            unavailable.note,
            SyncV2NoteSnapshot(
              versions: unavailable.versions,
              pendingIds: {'pending'},
            ),
            [],
          ),
          SyncV2WorkspaceNote(
            deleted.note.copyWith(deletedAt: now),
            deleted.snapshot,
            [],
          ),
          _note(
            'other',
            title: 'Other profile secret',
            body: 'hidden',
            createdAt: now,
            profileId: 'private',
          ),
        ];
      addTearDown(c.dispose);
      await mount(tester, c, displayStyle: null);
      await selectDisplayStyle(tester, SyncV2DisplayStyle.simple);
      await tester.tap(find.byKey(const ValueKey('sync-v2-calendar-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sync-v2-calendar')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('sync-v2-calendar-note-today')),
        200,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('sync-v2-calendar')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text('Calendar visible note'), findsOneWidget);
      expect(find.text('Other profile secret'), findsNothing);
      expect(find.text('Unavailable secret'), findsNothing);
      expect(find.text('Deleted secret'), findsNothing);
      await tester.ensureVisible(find.text('Calendar visible note'));
      final calendarNote = find.byKey(
        const ValueKey('sync-v2-calendar-note-today'),
      );
      await tester.ensureVisible(calendarNote);
      await tester.pumpAndSettle();
      await tester.tap(calendarNote);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('sync-v2-preview-back')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();
      final title = find.byKey(const Key('sync-v2-title'));
      await tester.enterText(title, 'Unsaved calendar draft');
      final toggle = tester.widget<IconButton>(
        find.byKey(const ValueKey('sync-v2-calendar-toggle')),
      );
      expect(toggle.onPressed, isNull);
      expect(
        tester.widget<TextField>(title).controller!.text,
        'Unsaved calendar draft',
      );
      c.lockPrivate();
      await tester.pumpAndSettle();
      expect(find.text('Unsaved calendar draft'), findsNothing);
      expect(find.text('Calendar visible note'), findsNothing);
    },
  );

  testWidgets('tags filter the current profile and are saved with the note', (
    tester,
  ) async {
    final now = DateTime.now();
    final c = _Controller()
      ..registered = true
      ..selectedProfileId = 'normal'
      ..notes = [
        _note(
          'tagged',
          title: 'Tagged note',
          body: '',
          createdAt: now,
          tags: ['Work'],
        ),
        _note('untagged', title: 'Untagged note', body: '', createdAt: now),
        _note(
          'private',
          title: 'Private note',
          body: '',
          createdAt: now,
          tags: ['Secret'],
          profileId: 'private',
        ),
      ];
    addTearDown(c.dispose);
    await mount(tester, c, displayStyle: null);
    expect(find.text('Work (1)'), findsOneWidget);
    expect(find.text('Secret'), findsNothing);
    expect(find.text('Secret (1)'), findsNothing);
    await tester.tap(find.text('Work (1)'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sync-v2-filter-count')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Tagged note'),
      180,
      scrollable: find
          .descendant(
            of: find.byType(HomeNotePreviewList),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Tagged note'), findsOneWidget);
    expect(find.text('Untagged note'), findsNothing);
    await openEditorFromList(tester, find.text('Tagged note'));
    expect(find.widgetWithText(InputChip, 'Work'), findsOneWidget);
    final pinButton = find.byKey(const ValueKey('sync-v2-note-pin'));
    expect(pinButton, findsOneWidget);
    await tester.ensureVisible(pinButton);
    await tester.tap(pinButton);
    await tester.enterText(
      find.byKey(const ValueKey('sync-v2-tag-input')),
      '#Family',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('sync-v2-tag-add')));
    await tester.tap(find.byKey(const ValueKey('sync-v2-tag-add')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(c.savedTags, ['Work', 'Family']);
    expect(c.savedPinned, isTrue);
    c.lockPrivate();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sync-v2-tag-chips')), findsNothing);
    expect(find.text('Work (1)'), findsNothing);
  });

  testWidgets('archives a note and restores it from the archive view', (
    tester,
  ) async {
    final c = _Controller()
      ..registered = true
      ..selectedProfileId = 'normal'
      ..notes = [
        _note(
          'archive-me',
          title: 'Archive me',
          body: 'Keep my original body',
          createdAt: DateTime.now(),
          tags: ['Work'],
          blocks: const [
            NoteBlock(
              type: NoteBlockType.paragraph,
              text: 'Keep my original body',
            ),
          ],
        ),
      ];
    addTearDown(c.dispose);
    await mount(tester, c);

    await openEditorFromList(tester, find.text('Archive me'));
    expect(c.busy, isFalse);
    expect(c.notes.single.ready, isTrue);
    final titleField = find.byKey(const Key('sync-v2-title'));
    await tester.enterText(titleField, 'Unsaved title');
    await tester.pumpAndSettle();
    final bodyField = find.byKey(const Key('sync-v2-body'));
    expect(bodyField, findsOneWidget);
    await tester.enterText(bodyField, 'Unsaved body and rich block');
    await tester.pumpAndSettle();
    final archiveAction = find.byKey(const ValueKey('sync-v2-note-archive'));
    expect(tester.widget<IconButton>(archiveAction).onPressed, isNull);
    expect(
      tester.widget<TextField>(titleField).controller!.text,
      'Unsaved title',
    );
    expect(
      tester.widget<TextField>(bodyField).controller!.text,
      'Unsaved body and rich block',
    );

    await tester.enterText(titleField, 'Archive me');
    await tester.enterText(bodyField, 'Keep my original body');
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(archiveAction).onPressed, isNotNull);
    final staleArchiveCallback = tester
        .widget<IconButton>(archiveAction)
        .onPressed!;
    final tagField = find.byKey(const ValueKey('sync-v2-tag-input'));
    await tester.ensureVisible(tagField);
    await tester.enterText(tagField, 'Unsaved tag');
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(archiveAction).onPressed, isNull);
    staleArchiveCallback();
    await tester.pumpAndSettle();
    expect(c.savedArchived, isNull);
    expect(find.byKey(const Key('sync-v2-title')), findsOneWidget);
    expect(tester.widget<TextField>(tagField).controller!.text, 'Unsaved tag');
    await tester.enterText(tagField, '');
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(archiveAction).onPressed, isNotNull);
    await tester.ensureVisible(archiveAction);
    await tester.tap(archiveAction);
    await tester.pumpAndSettle();
    expect(c.savedArchived, isTrue);
    expect(find.text('Archive me'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('sync-v2-archive-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sync-v2-archive')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('sync-v2-archive-note-archive-me')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('sync-v2-unarchive-archive-me')),
    );
    await tester.pumpAndSettle();
    expect(c.savedArchived, isFalse);
    expect(
      find.byKey(const ValueKey('sync-v2-archive-note-archive-me')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('sync-v2-calendar-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sync-v2-calendar')), findsOneWidget);
    expect(find.byKey(const ValueKey('sync-v2-archive')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('sync-v2-insights-toggle')));
    await tester.pumpAndSettle();
    expect(find.byType(SyncV2InsightsView), findsOneWidget);
    expect(find.byKey(const ValueKey('sync-v2-archive')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('sync-v2-trash-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sync-v2-trash')), findsOneWidget);
    expect(find.byKey(const ValueKey('sync-v2-archive')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('sync-v2-archive-toggle')));
    await tester.pumpAndSettle();
    c.lockPrivate();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sync-v2-archive')), findsNothing);
    expect(find.text('Archive me'), findsNothing);
    c.notes = [
      _note(
        'stale-private',
        title: 'Stale private note',
        body: 'must stay hidden after lock',
        createdAt: DateTime.now(),
        profileId: 'private',
      ),
    ];
    c.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Stale private note'), findsNothing);
  });

  testWidgets('tag management confirms deletion for selected profile', (
    tester,
  ) async {
    final c = _Controller()
      ..registered = true
      ..selectedProfileId = 'normal'
      ..notes = [
        _note(
          'tagged',
          title: 'Tagged note',
          body: '',
          createdAt: DateTime.now(),
          tags: ['Work'],
        ),
      ];
    addTearDown(c.dispose);
    await mount(tester, c, displayStyle: null);
    await tester.tap(find.byKey(const ValueKey('sync-v2-tag-manage')));
    await tester.pumpAndSettle();
    expect(find.text('Manage tags'), findsOneWidget);
    await tester.tap(find.byTooltip('Rename'));
    await tester.pumpAndSettle();
    final input = find.byType(TextField).last;
    expect(tester.widget<TextField>(input).obscureText, isFalse);
    await tester.enterText(input, 'Renamed');
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(c.managedTag, 'Work');
    expect(c.renamedTag, 'Renamed');
    c.managedTag = null;
    await tester.tap(find.byKey(const ValueKey('sync-v2-tag-manage')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete tag'));
    await tester.pumpAndSettle();
    expect(c.managedTag, isNull);
    expect(
      find.descendant(
        of: find.byType(AlertDialog).last,
        matching: find.byKey(const ValueKey('sync-v2-open-settings')),
      ),
      findsNothing,
    );
    await tester.tap(find.text('Confirm and continue'));
    await tester.pumpAndSettle();
    expect(c.managedTag, 'Work');
  });

  testWidgets('simple view preference persists after remount', (tester) async {
    final c = _Controller()
      ..registered = true
      ..selectedProfileId = 'normal'
      ..notes = [
        _note(
          'persist-note',
          title: 'Persistent note',
          body: 'Body',
          createdAt: DateTime.utc(2025),
        ),
      ];
    addTearDown(c.dispose);
    await mount(tester, c, displayStyle: null);
    expect(find.byType(HomeNotePreviewList), findsOneWidget);
    await selectDisplayStyle(tester, SyncV2DisplayStyle.simple);
    expect(find.byType(HomeNotePreviewList), findsNothing);
    expect(find.byKey(const ValueKey('sync-v2-search')), findsNothing);
    expect(
      (await SharedPreferences.getInstance()).getString(
        syncV2DisplayStylePreference,
      ),
      'simple',
    );
    await mount(tester, c, resetDisplayStyle: false);
    expect(find.byType(HomeNotePreviewList), findsNothing);
    expect(find.byKey(const ValueKey('sync-v2-search')), findsNothing);
    expect(find.text('Persistent note'), findsOneWidget);
  });

  testWidgets('switching designs preserves the open note draft', (
    tester,
  ) async {
    final c = _Controller()
      ..registered = true
      ..selectedProfileId = 'normal'
      ..notes = [
        _note(
          'draft-note',
          title: 'Saved title',
          body: 'Saved body',
          createdAt: DateTime.utc(2025),
        ),
      ];
    addTearDown(c.dispose);
    await mount(tester, c, displayStyle: null);
    await tester.ensureVisible(find.text('Saved title'));
    await openEditorFromList(tester, find.text('Saved title'));
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('sync-v2-profile-actions')),
          )
          .onPressed,
      isNull,
    );
    final title = find.byKey(const Key('sync-v2-title'));
    final body = find.byKey(const Key('sync-v2-body'));
    await tester.enterText(title, 'Unsaved title draft');
    await tester.enterText(body, 'Unsaved private draft');
    await tester.pump();

    await selectDisplayStyle(tester, SyncV2DisplayStyle.simple);
    expect(
      tester.widget<TextField>(title).controller!.text,
      'Unsaved title draft',
    );
    expect(
      tester.widget<TextField>(body).controller!.text,
      'Unsaved private draft',
    );
    await selectDisplayStyle(tester, SyncV2DisplayStyle.original);
    expect(
      tester.widget<TextField>(title).controller!.text,
      'Unsaved title draft',
    );
    expect(
      tester.widget<TextField>(body).controller!.text,
      'Unsaved private draft',
    );
    expect(c.savedOriginal, isNull);
    expect(c.chosenVersion, isNull);
    expect(c.registered, isTrue);
  });

  testWidgets('copies only the explicitly open v2 draft text', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final clipboard = <String, Object?>{};
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard['text'] = (call.arguments as Map)['text'];
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final c = _Controller()
      ..registered = true
      ..selectedProfileId = 'normal'
      ..notes = [
        _note(
          'shareable',
          title: 'Saved title',
          body: 'Saved body',
          tags: ['Work'],
          createdAt: DateTime.utc(2025),
        ),
      ];
    addTearDown(c.dispose);
    await mount(tester, c, displayStyle: null);
    await tester.ensureVisible(find.text('Saved title'));
    await openEditorFromList(tester, find.text('Saved title'));
    await tester.enterText(
      find.byKey(const Key('sync-v2-title')),
      'Draft title',
    );
    await tester.enterText(find.byKey(const Key('sync-v2-body')), 'Draft body');
    final copyButton = find.byKey(const ValueKey('sync-v2-copy-draft-text'));
    await tester.ensureVisible(copyButton);
    await tester.tap(copyButton);
    await tester.pumpAndSettle();
    expect(clipboard['text'], 'Draft title\n\nDraft body\n\n#Work');
    expect(find.text('Note text copied.'), findsOneWidget);
    expect(c.savedOriginal, isNull);
  });

  testWidgets('dismissed share sheet reports no successful share', (
    tester,
  ) async {
    final shareChannel = const MethodChannel('dev.fluttercommunity.plus/share');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannel, (call) async {
          calls.add(call);
          return '';
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(shareChannel, null),
    );
    final c = _Controller()
      ..registered = true
      ..selectedProfileId = 'normal'
      ..notes = [
        _note(
          'share-cancel',
          title: 'Share title',
          body: 'Share body',
          createdAt: DateTime.utc(2025),
        ),
      ];
    addTearDown(c.dispose);
    await mount(tester, c);
    await openEditorFromList(tester, find.text('Share title'));
    final shareButton = find.byKey(const ValueKey('sync-v2-share-draft-text'));
    await tester.ensureVisible(shareButton);
    await tester.tap(shareButton);
    await tester.pumpAndSettle();
    expect(calls.single.method, 'share');
    expect(
      (calls.single.arguments as Map)['text'],
      'Share title\n\nShare body',
    );
    expect((calls.single.arguments as Map).containsKey('paths'), isFalse);
    expect(find.text('Note text shared.'), findsNothing);
  });

  testWidgets('settings navigation locks v2 and permits returning', (
    tester,
  ) async {
    final c = _Controller()
      ..registered = true
      ..selectedProfileId = 'normal';
    addTearDown(c.dispose);
    final router = GoRouter(
      initialLocation: '/sync-v2',
      routes: [
        GoRoute(
          path: '/sync-v2',
          builder: (_, _) => const SyncV2WorkspaceScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, _) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => context.go('/sync-v2'),
                child: const Text('Return to v2'),
              ),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [syncV2WorkspaceProvider.overrideWithValue(c)],
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppStrings.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sync-v2-open-settings')));
    await tester.pumpAndSettle();
    expect(find.text('Return to v2'), findsOneWidget);
    expect(c.backgroundCalled, isTrue);
    await tester.tap(find.text('Return to v2'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sync-v2-open-settings')), findsOneWidget);
  });

  testWidgets('settings shortcut is hidden in isolated previews', (
    tester,
  ) async {
    final c = _Controller()..registered = true;
    addTearDown(c.dispose);
    await mount(tester, c, localOnly: true);
    expect(find.byKey(const ValueKey('sync-v2-open-settings')), findsNothing);
    await mount(tester, c, cloudSandbox: true);
    expect(find.byKey(const ValueKey('sync-v2-open-settings')), findsNothing);
  });

  testWidgets('original list filters notes and exposes sort and density', (
    tester,
  ) async {
    final c = _Controller()
      ..registered = true
      ..selectedProfileId = 'normal'
      ..notes = [
        _note(
          'a',
          title: 'Needle title',
          body: 'First body',
          tags: ['violet-tag'],
          createdAt: DateTime.utc(2020),
          updatedAt: DateTime.utc(2024),
        ),
        _note(
          'b',
          title: 'Second title',
          body: 'Needle body',
          createdAt: DateTime.utc(2021),
          updatedAt: DateTime.utc(2023),
        ),
        _note(
          'c',
          title: 'Third title',
          body: 'Third body',
          tags: ['Needle tag'],
          createdAt: DateTime.utc(2022),
          updatedAt: DateTime.utc(2022),
        ),
      ];
    addTearDown(c.dispose);
    await mount(tester, c, displayStyle: null);
    HomeNotePreviewList list() =>
        tester.widget<HomeNotePreviewList>(find.byType(HomeNotePreviewList));
    final search = find.byKey(const ValueKey('sync-v2-search'));
    await tester.enterText(search, 'needle title');
    await tester.pumpAndSettle();
    expect(list().notes.map((note) => note.title), ['Needle title']);
    await tester.enterText(search, 'needle body');
    await tester.pumpAndSettle();
    expect(list().notes.map((note) => note.title), ['Second title']);
    await tester.enterText(search, 'needle tag');
    await tester.pumpAndSettle();
    expect(list().notes.map((note) => note.title), ['Third title']);
    await tester.enterText(search, '');
    await tester.pumpAndSettle();
    expect(list().notes.map((note) => note.title), [
      'Third title',
      'Second title',
      'Needle title',
    ]);
    await tester.tap(find.byKey(const ValueKey('sync-v2-search-filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<NotesListSortField>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Updated').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<NotesListDensity>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compact').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(list().sortField.name, 'updatedAt');
    expect(list().notes.map((note) => note.title), [
      'Needle title',
      'Second title',
      'Third title',
    ]);
    expect(list().density.name, 'compact');
  });

  testWidgets('draft search counts and moves through title and body matches', (
    tester,
  ) async {
    final c = _Controller()
      ..registered = true
      ..selectedProfileId = 'normal'
      ..notes = [
        _note(
          'search-note',
          title: 'needle title',
          body: 'body needle then needle again',
          createdAt: DateTime.utc(2025),
        ),
      ];
    addTearDown(c.dispose);
    await mount(tester, c, displayStyle: null);
    await openEditorFromList(tester, find.text('needle title'));

    final search = find.byKey(const ValueKey('sync-v2-draft-search'));
    final searchFocus = tester.widget<TextField>(search).focusNode!;
    await tester.enterText(search, 'n');
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, same(searchFocus));
    await tester.enterText(search, 'nee');
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, same(searchFocus));
    await tester.enterText(search, 'needle');
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, same(searchFocus));
    expect(find.text('1 / 3 · Title'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sync-v2-draft-search-next')));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3 · Body 1'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('sync-v2-body')))
          .controller!
          .selection
          .textInside('body needle then needle again'),
      'needle',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('sync-v2-body')))
          .controller!
          .text,
      'body needle then needle again',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('sync-v2-title')))
          .controller!
          .text,
      'needle title',
    );

    await tester.enterText(search, 'unique');
    await tester.pumpAndSettle();
    expect(find.text('No matches'), findsOneWidget);
    final title = find.byKey(const Key('sync-v2-title'));
    await tester.enterText(title, 'Unique title');
    await tester.pumpAndSettle();
    expect(find.text('1 / 1 · Title'), findsOneWidget);
    final titleFocus = tester.widget<TextField>(title).focusNode!;
    await tester.tap(find.byKey(const ValueKey('sync-v2-draft-search-next')));
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, same(titleFocus));
    await tester.enterText(title, 'Changed title');
    await tester.pumpAndSettle();
    expect(find.text('No matches'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sync-v2-draft-search-clear')));
    await tester.pumpAndSettle();
    expect(find.text('0 / 0'), findsOneWidget);
  });

  testWidgets('background clears original search and private editor draft', (
    tester,
  ) async {
    final c = _Controller()
      ..registered = true
      ..selectedProfileId = 'private_profile:notes'
      ..clearNotesOnBackground = true;
    c.availablePrivateProfiles.add(
      const SyncV2WorkspaceProfile('private_profile:notes', 'Private'),
    );
    c.notes = [
      _note(
        'private-note',
        title: 'Private note',
        body: 'Sensitive private text',
        createdAt: DateTime.utc(2025),
        profileId: 'private_profile:notes',
      ),
    ];
    addTearDown(c.dispose);
    await mount(tester, c, displayStyle: null);
    final search = find.byKey(const ValueKey('sync-v2-search'));
    await tester.enterText(search, 'private');
    await tester.pumpAndSettle();
    await openEditorFromList(tester, find.text('Private note'));
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('sync-v2-body')))
          .controller!
          .text,
      'Sensitive private text',
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(c.backgroundCalled, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(c.notes, isEmpty);
    expect(find.byKey(const Key('sync-v2-body')), findsNothing);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('sync-v2-search')))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('external private lock clears search and open editor state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = _Controller()
      ..registered = true
      ..selectedProfileId = 'private_profile:notes';
    c.availablePrivateProfiles.add(
      const SyncV2WorkspaceProfile('private_profile:notes', 'Private'),
    );
    c.notes = [
      _note(
        'external-lock-note',
        title: 'Private note',
        body: 'Sensitive source text',
        createdAt: DateTime.utc(2025),
        profileId: 'private_profile:notes',
      ),
    ];
    addTearDown(c.dispose);
    await mount(tester, c, displayStyle: null);
    final search = find.byKey(const ValueKey('sync-v2-search'));
    await tester.enterText(search, 'private');
    await tester.pumpAndSettle();
    final searchStateBeforeLock = tester.state(search);
    await openEditorFromList(tester, find.text('Private note'));
    await tester.enterText(
      find.byKey(const Key('sync-v2-title')),
      'Unsaved private title',
    );
    await tester.enterText(
      find.byKey(const Key('sync-v2-body')),
      'Unsaved private draft',
    );
    await tester.pump();

    c.lockPrivate();
    await tester.pumpAndSettle();
    expect(c.selectedProfileId, isNull);
    expect(c.notes, isEmpty);
    expect(find.byKey(const Key('sync-v2-title')), findsNothing);
    expect(find.byKey(const Key('sync-v2-body')), findsNothing);
    expect(tester.state(search), isNot(same(searchStateBeforeLock)));
    expect(tester.widget<TextFormField>(search).controller!.text, isEmpty);
  });

  testWidgets('external lock closes a profile popup holding private names', (
    tester,
  ) async {
    final c = _Controller()
      ..registered = true
      ..selectedProfileId = 'normal';
    c.availablePrivateProfiles.add(
      const SyncV2WorkspaceProfile('private_profile:secret', 'SecretName'),
    );
    addTearDown(c.dispose);
    await mount(tester, c, displayStyle: null);
    await tester.tap(find.byKey(const ValueKey('sync-v2-profile-actions')));
    await tester.pumpAndSettle();
    final profiles = find.byType(DropdownButton<String>).first;
    await tester.tap(profiles);
    await tester.pumpAndSettle();
    expect(find.text('SecretName'), findsOneWidget);

    c.availablePrivateProfiles.clear();
    c.lockPrivate();
    await tester.pumpAndSettle();
    expect(find.text('SecretName'), findsNothing);
    expect(find.byType(SyncV2WorkspaceScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('external lock closes only the named admin menu route', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = _Controller()
      ..registered = true
      ..selectedProfileId = 'normal'
      ..isAdmin = true
      ..profileConflicts = [
        const SyncV2WorkspaceProfile(
          'private_profile:secret-conflict',
          'SecretConflict',
        ),
      ];
    addTearDown(c.dispose);
    await mount(tester, c, displayStyle: null);
    await tester.tap(find.byKey(const ValueKey('sync-v2-profile-actions')));
    await tester.pumpAndSettle();
    final screenContext = tester.element(find.byType(SyncV2WorkspaceScreen));
    final navigator = Navigator.of(screenContext, rootNavigator: true);
    unawaited(
      navigator.push<void>(
        DialogRoute<void>(
          context: screenContext,
          builder: (context) => AlertDialog(
            title: const Text('External authentication dialog'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close external dialog'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('External authentication dialog'), findsOneWidget);

    final adminMenu = find.byType(PopupMenuButton<String>);
    tester.state<PopupMenuButtonState<String>>(adminMenu).showButtonMenu();
    await tester.pumpAndSettle();
    expect(find.text('Repair conflict: SecretConflict'), findsOneWidget);

    c.lockPrivate();
    await tester.pumpAndSettle();
    expect(find.text('Repair conflict: SecretConflict'), findsNothing);
    expect(find.text('External authentication dialog'), findsOneWidget);
    expect(find.byType(SyncV2WorkspaceScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Close external dialog'));
    await tester.pumpAndSettle();
    expect(find.byType(SyncV2WorkspaceScreen), findsOneWidget);
    expect(find.text('External authentication dialog'), findsNothing);
  });

  testWidgets('biometric first registration does not ask for a password', (
    tester,
  ) async {
    final controller = _Controller()..biometricsAvailable = true;
    addTearDown(controller.dispose);
    await mount(tester, controller);
    await tester.tap(find.text('Create with Face ID / Touch ID'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('SYNC-secret-code'), findsOneWidget);
    expect(controller.passwords, isEmpty);
    expect(controller.confirmations, 0);
  });

  testWidgets(
    'system biometric inactive does not cancel setup but background still locks',
    (tester) async {
      final controller = _Controller()..biometricAuthenticating = true;
      addTearDown(controller.dispose);
      await mount(tester, controller);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(controller.backgroundCalled, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(controller.backgroundCalled, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'biometric success before resumed waits then shows recovery codes',
    (tester) async {
      final release = Completer<void>();
      final controller = _Controller()..biometricsAvailable = true;
      addTearDown(controller.dispose);
      controller.biometricDelay = () {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        return release.future;
      };
      await mount(tester, controller);
      await tester.tap(find.text('Create with Face ID / Touch ID'));
      await tester.pump();
      expect(controller.backgroundCalled, isFalse);
      release.complete();
      await tester.pumpAndSettle();
      expect(find.text('SYNC-secret-code'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('SYNC-secret-code'), findsOneWidget);
      expect(controller.confirmations, 0);
      expect(controller.cancellations, 0);
    },
  );

  testWidgets('real background after biometric success discards code display', (
    tester,
  ) async {
    final release = Completer<void>();
    final controller = _Controller()..biometricsAvailable = true;
    addTearDown(controller.dispose);
    controller.biometricDelay = () {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      return release.future;
    };
    await mount(tester, controller);
    await tester.tap(find.text('Create with Face ID / Touch ID'));
    await tester.pump();
    release.complete();
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(controller.backgroundCalled, isTrue);
    expect(find.text('SYNC-secret-code'), findsNothing);
    expect(controller.confirmations, 0);
    expect(controller.cancellations, 0);
  });

  Future<void> mountImportReview(
    WidgetTester tester,
    _Controller c, {
    required Map<String, int> counts,
    int unlinked = 0,
    Future<void> Function()? unlockAdmin,
    Future<void> Function()? unlockPrivate,
    Future<void> Function()? recoverAdmin,
    Future<String?> Function()? create,
    void Function(SyncV2ImportSelection?)? selected,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final result = await showDialog<SyncV2ImportSelection>(
                  context: context,
                  builder: (_) => SyncV2ImportReviewDialog(
                    controller: c,
                    inspection: SyncV2ArchiveInspection(counts, unlinked),
                    isActive: () => true,
                    errorMessage: (code) => code,
                    unlockAdmin: unlockAdmin ?? () async {},
                    unlockAdminWithPassword: () async {},
                    unlockPrivate: unlockPrivate ?? () async {},
                    recoverAdmin: recoverAdmin ?? () async {},
                    createDestination: create ?? () async => null,
                  ),
                );
                selected?.call(result);
              },
              child: const Text('Review ZIP'),
            ),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Review ZIP'));
    await tester.tap(find.text('Review ZIP'));
    await tester.pumpAndSettle();
  }

  testWidgets('unregistered QR join confirms and calls only sync recovery', (
    tester,
  ) async {
    final c = _Controller();
    addTearDown(c.dispose);
    await mount(
      tester,
      c,
      scannerBuilder: (_) => _scannerDialog(_syncPairingCode()),
    );
    await tester.tap(find.byKey(const ValueKey('sync-v2-scan-join')));
    await tester.pumpAndSettle();
    expect(find.text('Fake scanner'), findsOneWidget);
    await tester.tap(find.text('Return scanned code'));
    await tester.pumpAndSettle();
    expect(find.text('Join the existing workspace'), findsOneWidget);
    await tester.tap(find.text('Confirm and continue'));
    await tester.pumpAndSettle();
    expect(c.recoveryCodes, [_syncPairingCode()]);
    expect(c.pairingEvents, ['sync:${_syncPairingCode()}']);
    expect(c.adminRecoveryCodes, isEmpty);
    expect(c.prepared, isFalse);
    expect(c.passwords, isEmpty);
  });

  testWidgets('cancelled pairing scan or confirmation never recovers', (
    tester,
  ) async {
    final cancelledScan = _Controller();
    addTearDown(cancelledScan.dispose);
    await mount(
      tester,
      cancelledScan,
      scannerBuilder: (_) => _scannerDialog(_syncPairingCode()),
    );
    await tester.tap(find.byKey(const ValueKey('sync-v2-scan-join')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel scan'));
    await tester.pumpAndSettle();
    expect(cancelledScan.recoveryCodes, isEmpty);
    expect(cancelledScan.prepared, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    final cancelledConfirmation = _Controller();
    addTearDown(cancelledConfirmation.dispose);
    await mount(
      tester,
      cancelledConfirmation,
      scannerBuilder: (_) => _scannerDialog(_syncPairingCode()),
    );
    await tester.tap(find.byKey(const ValueKey('sync-v2-scan-join')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Return scanned code'));
    await tester.pumpAndSettle();
    expect(find.text('Join the existing workspace'), findsOneWidget);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(cancelledConfirmation.recoveryCodes, isEmpty);
    expect(cancelledConfirmation.prepared, isFalse);
  });

  testWidgets('pairing scan waits through inactive and closes on background', (
    tester,
  ) async {
    final waiting = _Controller();
    addTearDown(waiting.dispose);
    await mount(
      tester,
      waiting,
      scannerBuilder: (_) => _scannerDialog(_syncPairingCode()),
    );
    await tester.tap(find.byKey(const ValueKey('sync-v2-scan-join')));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(waiting.backgroundCalled, isFalse);
    await tester.tap(find.text('Return scanned code'));
    await tester.pump();
    expect(find.text('Join the existing workspace'), findsNothing);
    expect(waiting.recoveryCodes, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Join the existing workspace'), findsOneWidget);
    await tester.tap(find.text('Confirm and continue'));
    await tester.pumpAndSettle();
    expect(waiting.recoveryCodes, [_syncPairingCode()]);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    final backgrounded = _Controller();
    addTearDown(backgrounded.dispose);
    final lateCode = Completer<String?>();
    await mount(
      tester,
      backgrounded,
      scannerBuilder: (_) => _PendingScanner(lateCode),
    );
    await tester.tap(find.byKey(const ValueKey('sync-v2-scan-join')));
    await tester.pumpAndSettle();
    expect(find.text('Pending fake scanner'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(backgrounded.backgroundCalled, isTrue);
    lateCode.complete(_syncPairingCode());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Pending fake scanner'), findsNothing);
    expect(find.text('Join the existing workspace'), findsNothing);
    expect(backgrounded.recoveryCodes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('registered non-admin can show sync QR without admin code', (
    tester,
  ) async {
    final c = _Controller()..registered = true;
    addTearDown(c.dispose);
    await mount(tester, c);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Add another device with QR'), findsOneWidget);
    expect(find.text('Show administrator QR'), findsNothing);
    await tester.tap(find.text('Add another device with QR'));
    await tester.pumpAndSettle();
    expect(c.recoveryCodeDisplayCalls, 1);
    final syncQr = tester.widget<SyncV2PairingQrDialog>(
      find.byType(SyncV2PairingQrDialog),
    );
    expect(syncQr.code, _syncPairingCode());
    expect(syncQr.administrator, isFalse);
    expect(
      find.byKey(const ValueKey('sync-v2-pairing-qr-image')),
      findsOneWidget,
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    c.isAdmin = true;
    c.notifyListeners();
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Show administrator QR'), findsOneWidget);
  });

  testWidgets('administrator QR scan uses biometric admin recovery', (
    tester,
  ) async {
    final c = _Controller()
      ..registered = true
      ..biometricsAvailable = true;
    addTearDown(c.dispose);
    await mount(
      tester,
      c,
      scannerBuilder: (administrator) {
        expect(administrator, isTrue);
        return _scannerDialog(_adminPairingCode());
      },
    );
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Scan administrator QR'), findsOneWidget);
    await tester.ensureVisible(find.text('Scan administrator QR'));
    await tester.tap(find.text('Scan administrator QR'));
    await tester.pumpAndSettle();
    expect(find.text('Fake scanner'), findsOneWidget);
    await tester.tap(find.text('Return scanned code'));
    await tester.pumpAndSettle();
    expect(find.text('Register this device as administrator'), findsOneWidget);
    await tester.tap(find.text('Confirm and continue'));
    await tester.pumpAndSettle();
    expect(c.adminRecoveryCodes, [_adminPairingCode()]);
    expect(c.recoveryCodes, isEmpty);
    expect(c.pairingEvents, ['admin:${_adminPairingCode()}']);
  });

  OutlinedButton importButton(WidgetTester tester) =>
      tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Import to selected destinations'),
      );

  Finder adminImportButton(WidgetTester tester) =>
      find.byKey(const ValueKey('import-admin-overwrite'));

  Future<void> tapAdminImport(WidgetTester tester) async {
    final button = adminImportButton(tester);
    await tester.ensureVisible(button);
    await tester.tap(button);
  }

  testWidgets(
    'administrator overwrite stays enabled without destinations or attachment consent',
    (tester) async {
      final c = _Controller();
      addTearDown(c.dispose);
      SyncV2ImportSelection? selection;
      await mountImportReview(
        tester,
        c,
        counts: {
          'everyday': 33,
          'private': 20,
          'private_profile:two': 3,
          'private_profile:three': 1,
        },
        unlinked: 7,
        unlockAdmin: () async {
          c.isAdmin = true;
          c.notifyListeners();
        },
        selected: (value) => selection = value,
      );
      final button = tester.widget<FilledButton>(adminImportButton(tester));
      expect(button.onPressed, isNotNull);
      expect(find.byType(CheckboxListTile), findsOneWidget);
      expect(
        find.textContaining('private destinations are prepared automatically'),
        findsOneWidget,
      );
      await tapAdminImport(tester);
      await tester.pumpAndSettle();
      expect(selection?.administratorOverwrite, isTrue);
      expect(selection?.destinations, isEmpty);
      expect(selection?.acceptUnlinkedAttachments, isTrue);
    },
  );

  testWidgets(
    'cancelled or unsuccessful admin authentication keeps review open',
    (tester) async {
      for (final succeeds in [false, true]) {
        final c = _Controller();
        addTearDown(c.dispose);
        SyncV2ImportSelection? selection;
        await mountImportReview(
          tester,
          c,
          counts: {'private': 1},
          unlockAdmin: () async {
            if (succeeds) {
              c.isAdmin = true;
              c.notifyListeners();
            }
          },
          selected: (value) => selection = value,
        );
        await tapAdminImport(tester);
        await tester.pumpAndSettle();
        if (!succeeds) {
          expect(find.text('Review import'), findsOneWidget);
          expect(selection, isNull);
          await tester.tap(find.text('Cancel').last);
          await tester.pumpAndSettle();
        } else {
          expect(find.text('Review import'), findsNothing);
          expect(selection?.administratorOverwrite, isTrue);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    'empty workspace can authenticate and create three distinct ZIP destinations',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = _Controller()..biometricEnabled = true;
      addTearDown(c.dispose);
      SyncV2ImportSelection? imported;
      var authenticated = 0;
      await mountImportReview(
        tester,
        c,
        counts: {
          'everyday': 33,
          'private': 20,
          'private_profile:two': 3,
          'private_profile:three': 1,
        },
        unlinked: 7,
        unlockAdmin: () async {
          authenticated++;
          c.isAdmin = true;
          c.notifyListeners();
        },
        create: () async {
          expect(c.adminUnlocked, isTrue);
          final id =
              'private_profile:destination${c.availablePrivateProfiles.length + 1}';
          c.availablePrivateProfiles.add(
            SyncV2WorkspaceProfile(
              id,
              'Destination ${c.availablePrivateProfiles.length + 1}',
            ),
          );
          c.notifyListeners();
          return id;
        },
        selected: (value) => imported = value,
      );
      expect(
        find.textContaining('Destinations are missing or locked'),
        findsOneWidget,
      );
      expect(importButton(tester).onPressed, isNull);
      await tester.tap(find.text('Show profiles with biometrics'));
      await tester.pumpAndSettle();
      expect(authenticated, 1);
      for (final source in [
        'private',
        'private_profile:two',
        'private_profile:three',
      ]) {
        final create = find.byKey(ValueKey('import-create-$source'));
        await tester.ensureVisible(create);
        await tester.tap(create);
        await tester.pumpAndSettle();
      }
      expect(c.availablePrivateProfiles, hasLength(3));
      expect(
        importButton(tester).onPressed,
        isNull,
        reason: 'Missing attachment consent still required',
      );
      final consent = find.byType(CheckboxListTile);
      await tester.ensureVisible(consent);
      await tester.tap(consent);
      await tester.pumpAndSettle();
      expect(importButton(tester).onPressed, isNotNull);
      await tester.tap(find.text('Import to selected destinations'));
      await tester.pumpAndSettle();
      expect(
        imported!.destinations.keys,
        unorderedEquals([
          'private',
          'private_profile:two',
          'private_profile:three',
        ]),
      );
      expect(imported!.destinations.values.toSet(), hasLength(3));
      expect(
        imported!.destinations.values,
        everyElement(startsWith('private_profile:')),
      );
      expect(imported!.acceptUnlinkedAttachments, isTrue);
    },
  );

  testWidgets(
    'locked ZIP destination can be unlocked without selecting the ZIP again',
    (tester) async {
      final c = _Controller();
      addTearDown(c.dispose);
      var cancel = true;
      SyncV2ImportSelection? imported;
      await mountImportReview(
        tester,
        c,
        counts: {'private': 1},
        unlockPrivate: () async {
          if (cancel) return;
          c.availablePrivateProfiles.add(
            const SyncV2WorkspaceProfile(
              'private_profile:existing',
              'Existing private',
            ),
          );
          c.notifyListeners();
        },
        selected: (value) => imported = value,
      );
      await tester.tap(find.text('Unlock existing profile'));
      await tester.pumpAndSettle();
      expect(find.text('Review import'), findsOneWidget);
      expect(importButton(tester).onPressed, isNull);
      cancel = false;
      await tester.tap(find.text('Unlock existing profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Existing private').last);
      await tester.pumpAndSettle();
      expect(importButton(tester).onPressed, isNotNull);
      await tester.tap(find.text('Import to selected destinations'));
      await tester.pumpAndSettle();
      expect(imported!.destinations, {'private': 'private_profile:existing'});
    },
  );

  testWidgets(
    'cancelled creation and duplicate destination cannot enable ZIP import',
    (tester) async {
      final c = _Controller();
      addTearDown(c.dispose);
      var cancelled = true;
      await mountImportReview(
        tester,
        c,
        counts: {'private': 1, 'private_profile:two': 1},
        create: () async {
          if (cancelled) return null;
          if (c.availablePrivateProfiles.isEmpty) {
            c.availablePrivateProfiles.add(
              const SyncV2WorkspaceProfile('private_profile:one', 'One'),
            );
          }
          c.notifyListeners();
          return 'private_profile:one';
        },
      );
      final create = find.byKey(const ValueKey('import-create-private'));
      await tester.ensureVisible(create);
      await tester.tap(create);
      await tester.pumpAndSettle();
      expect(importButton(tester).onPressed, isNull);
      cancelled = false;
      await tester.ensureVisible(
        find.byKey(const ValueKey('import-create-private')),
      );
      await tester.tap(find.byKey(const ValueKey('import-create-private')));
      await tester.pumpAndSettle();
      final secondCreate = find.byKey(
        const ValueKey('import-create-private_profile:two'),
      );
      await tester.ensureVisible(secondCreate);
      await tester.tap(secondCreate);
      await tester.pumpAndSettle();
      expect(importButton(tester).onPressed, isNull);
      final fields = tester
          .widgetList<DropdownButton<String>>(
            find.byType(DropdownButton<String>),
          )
          .toList();
      expect(
        fields[1].items,
        isEmpty,
        reason: 'Already assigned destination is not offered twice',
      );
    },
  );

  testWidgets(
    'closing review while creation is pending does not import or update a disposed dialog',
    (tester) async {
      final c = _Controller();
      addTearDown(c.dispose);
      final release = Completer<String?>();
      SyncV2ImportSelection? imported;
      await mountImportReview(
        tester,
        c,
        counts: {'private': 1},
        create: () => release.future,
        selected: (value) => imported = value,
      );
      final create = find.byKey(const ValueKey('import-create-private'));
      await tester.ensureVisible(create);
      await tester.tap(create);
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      release.complete('private_profile:late');
      await tester.pumpAndSettle();
      expect(imported, isNull);
      expect(find.text('Review import'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'normal-only ZIP requires no private authentication or destination',
    (tester) async {
      final c = _Controller();
      addTearDown(c.dispose);
      await mountImportReview(tester, c, counts: {'everyday': 33});
      expect(find.text('Unlock existing profile'), findsNothing);
      expect(
        find.textContaining('Destinations are missing or locked'),
        findsNothing,
      );
      expect(importButton(tester).onPressed, isNotNull);
    },
  );

  void installArchivePicker(
    WidgetTester tester, {
    Future<void> Function()? onPickerCalled,
  }) {
    final original = FilePickerPlatform.instance;
    FilePickerPlatform.instance = _ArchivePicker(
      onPickerCalled: onPickerCalled,
    );
    addTearDown(() => FilePickerPlatform.instance = original);
  }

  Future<void> openPickedArchive(
    WidgetTester tester, {
    Future<void> Function()? onPickerCalled,
  }) async {
    installArchivePicker(tester, onPickerCalled: onPickerCalled);
    await tester.ensureVisible(find.text('Import ZIP'));
    await tester.tap(find.text('Import ZIP'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Review import'), findsOneWidget);
  }

  testWidgets(
    'inactive ZIP picker waits for resume before asking for ZIP password',
    (tester) async {
      final c = _Controller()
        ..registered = true
        ..isAdmin = true;
      addTearDown(c.dispose);
      final pickerStarted = Completer<void>();
      final selectionReady = Completer<void>();
      await mount(tester, c);
      installArchivePicker(
        tester,
        onPickerCalled: () {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          pickerStarted.complete();
          return selectionReady.future;
        },
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SyncV2WorkspaceScreen)),
      );
      await tester.ensureVisible(find.text('Import ZIP'));
      await tester.tap(find.text('Import ZIP'));
      await tester.pump();
      await pickerStarted.future;
      expect(container.read(syncV2SystemPickerProvider), isTrue);

      selectionReady.complete();
      await tester.pump();
      await tester.pump();
      expect(container.read(syncV2SystemPickerProvider), isTrue);
      expect(find.text('ZIP password (optional)'), findsNothing);
      expect(find.text('Review import'), findsNothing);
      expect(c.backgroundCalled, isFalse);
      expect(c.backgroundCalls, 0);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(container.read(syncV2SystemPickerProvider), isFalse);
      expect(find.byType(TextField), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Review import'), findsOneWidget);
      expect(c.inspectedArchivePassword, isNull);
      await tapAdminImport(tester);
      await tester.pumpAndSettle();
      expect(c.importedAdminOverwrite, isTrue);
    },
  );

  testWidgets('paused ZIP picker locks and discards its late selection', (
    tester,
  ) async {
    final c = _Controller()
      ..registered = true
      ..isAdmin = true;
    addTearDown(c.dispose);
    final pickerStarted = Completer<void>();
    final selectionReady = Completer<void>();
    await mount(tester, c);
    installArchivePicker(
      tester,
      onPickerCalled: () {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        pickerStarted.complete();
        return selectionReady.future;
      },
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SyncV2WorkspaceScreen)),
    );
    await tester.ensureVisible(find.text('Import ZIP'));
    await tester.tap(find.text('Import ZIP'));
    await tester.pump();
    await pickerStarted.future;
    expect(container.read(syncV2SystemPickerProvider), isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(c.backgroundCalled, isTrue);
    expect(c.backgroundCalls, 1);
    selectionReady.complete();
    await tester.pumpAndSettle();
    expect(container.read(syncV2SystemPickerProvider), isFalse);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Review import'), findsNothing);
    expect(c.importedAdminOverwrite, isNull);
    expect(tester.takeException(), isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
  });

  testWidgets('screen routes admin selection to the overwrite controller API', (
    tester,
  ) async {
    final c = _Controller()
      ..registered = true
      ..isAdmin = true;
    addTearDown(c.dispose);
    await mount(tester, c);
    await openPickedArchive(tester);
    await tapAdminImport(tester);
    await tester.pumpAndSettle();
    expect(c.importedAdminOverwrite, isTrue);
    expect(c.importedAcceptUnlinked, isTrue);
    expect(c.importedDestinations, isNull);
  });

  testWidgets(
    'settings admin mode unlocks ZIP overwrite without another credential prompt',
    (tester) async {
      final c = _Controller(settingsAdminActive: true)..registered = true;
      addTearDown(c.dispose);
      await mount(tester, c);
      await openPickedArchive(tester);
      expect(c.inspectedArchivePassword, isNull);
      await tapAdminImport(tester);
      await tester.pumpAndSettle();
      expect(c.settingsUnlockCalls, 1);
      expect(c.adminUnlocked, isTrue);
      expect(c.biometricUnlockCalls, 0);
      expect(c.adminPasswords, isEmpty);
      expect(c.importedAdminOverwrite, isTrue);
      expect(find.byType(TextField), findsNothing);
    },
  );

  testWidgets('without settings admin mode, ZIP uses v2 biometric auth', (
    tester,
  ) async {
    final c = _Controller()
      ..registered = true
      ..biometricEnabled = true;
    addTearDown(c.dispose);
    await mount(tester, c);
    await openPickedArchive(tester);
    await tapAdminImport(tester);
    await tester.pumpAndSettle();
    expect(c.settingsUnlockCalls, 0);
    expect(c.biometricUnlockCalls, 1);
    expect(c.adminPasswords, isEmpty);
    expect(c.importedAdminOverwrite, isTrue);
  });

  testWidgets(
    'settings mode without a saved v2 admin grant falls back to biometrics',
    (tester) async {
      final c = _Controller(settingsAdminActive: true)
        ..registered = true
        ..biometricEnabled = true
        ..settingsUnlockSucceeds = false;
      addTearDown(c.dispose);
      await mount(tester, c);
      await openPickedArchive(tester);
      await tapAdminImport(tester);
      await tester.pumpAndSettle();
      expect(c.settingsUnlockCalls, 1);
      expect(c.biometricUnlockCalls, 1);
      expect(c.adminPasswords, isEmpty);
      expect(c.importedAdminOverwrite, isTrue);
    },
  );

  testWidgets('failed admin password leaves review open without importing', (
    tester,
  ) async {
    final c = _Controller()..registered = true;
    c.failAdminUnlock = true;
    addTearDown(c.dispose);
    await mount(tester, c);
    await openPickedArchive(tester);
    await tapAdminImport(tester);
    await tester.pumpAndSettle();
    final passwordField = find.byType(TextField).first;
    await tester.ensureVisible(passwordField);
    await tester.enterText(passwordField, 'wrong password');
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Review import'), findsOneWidget);
    expect(c.importedAdminOverwrite, isNull);
    expect(c.adminPasswords, ['wrong password']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'screen background closes review even with a destination popup open',
    (tester) async {
      final c = _Controller()..registered = true;
      c.availablePrivateProfiles.add(
        const SyncV2WorkspaceProfile(
          'private_profile:existing',
          'Existing private',
        ),
      );
      addTearDown(c.dispose);
      await mount(tester, c);
      await openPickedArchive(tester);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Review import'), findsNothing);
      expect(find.text('Encrypted sync v2'), findsOneWidget);
      expect(c.importedDestinations, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'screen review survives biometric inactive and waits for resumed',
    (tester) async {
      final c = _Controller()
        ..registered = true
        ..biometricEnabled = true;
      addTearDown(c.dispose);
      final release = Completer<void>();
      c.importBiometricDelay = () {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        return release.future;
      };
      await mount(tester, c);
      await openPickedArchive(tester);
      await tester.tap(find.text('Show profiles with biometrics'));
      await tester.pump();
      release.complete();
      await tester.pumpAndSettle();
      expect(find.text('Review import'), findsOneWidget);
      expect(c.backgroundCalled, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Review import'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Existing private').last);
      await tester.pumpAndSettle();
      expect(importButton(tester).onPressed, isNotNull);
      await tester.tap(find.text('Import to selected destinations'));
      await tester.pumpAndSettle();
      expect(c.importedDestinations, {'private': 'private_profile:existing'});
    },
  );

  testWidgets(
    'screen background during biometric unlock does not reopen or import',
    (tester) async {
      final c = _Controller()
        ..registered = true
        ..biometricEnabled = true;
      addTearDown(c.dispose);
      final release = Completer<void>();
      c.importBiometricDelay = () {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        return release.future;
      };
      await mount(tester, c);
      await openPickedArchive(tester);
      await tapAdminImport(tester);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      release.complete();
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Review import'), findsNothing);
      expect(c.importedDestinations, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'removing the workspace closes its root navigator review dialog',
    (tester) async {
      final c = _Controller()..registered = true;
      addTearDown(c.dispose);
      final visible = ValueNotifier(true);
      final navigatorKey = GlobalKey<NavigatorState>();
      addTearDown(visible.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [syncV2WorkspaceProvider.overrideWithValue(c)],
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: ValueListenableBuilder<bool>(
              valueListenable: visible,
              builder: (context, show, _) => show
                  ? const SyncV2WorkspaceScreen()
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await openPickedArchive(tester);
      unawaited(
        navigatorKey.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Destination page')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      visible.value = false;
      await tester.pumpAndSettle();
      expect(find.text('Review import', skipOffstage: false), findsNothing);
      expect(find.text('Destination page'), findsOneWidget);
      expect(c.importedDestinations, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'invalidated biometrics keeps ADMIN recovery available in review',
    (tester) async {
      final c = _Controller()
        ..biometricEnabled = true
        ..biometricsAvailable = true
        ..error = 'biometric_unavailable';
      addTearDown(c.dispose);
      var recovered = false;
      await mountImportReview(
        tester,
        c,
        counts: {'private': 1},
        recoverAdmin: () async {
          recovered = true;
          c.isAdmin = true;
          c.notifyListeners();
        },
      );
      expect(find.text('Use admin password'), findsOneWidget);
      await tester.ensureVisible(
        find.text('Set up biometrics with ADMIN code'),
      );
      await tester.tap(find.text('Set up biometrics with ADMIN code'));
      await tester.pumpAndSettle();
      expect(recovered, isTrue);
      expect(c.adminUnlocked, isTrue);
    },
  );

  testWidgets('cloud registration requires both recovery acknowledgments', (
    tester,
  ) async {
    final controller = _Controller();
    addTearDown(controller.dispose);
    await mount(tester, controller);
    await tester.tap(find.text('Create workspace'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'long-password-123');
    await tester.enterText(fields.at(1), 'long-password-123');
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    FilledButton register() => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Register in cloud'),
    );
    expect(register().onPressed, isNull);
    await tester.tap(find.byType(CheckboxListTile).at(0));
    await tester.pump();
    expect(register().onPressed, isNull);
    await tester.tap(find.byType(CheckboxListTile).at(1));
    await tester.pump();
    expect(register().onPressed, isNotNull);
    await tester.tap(find.text('Register in cloud'));
    await tester.pumpAndSettle();
    expect(controller.confirmations, 1);
  });
  testWidgets('background clears editor and locks private workspace', (
    tester,
  ) async {
    final controller = _Controller()
      ..registered = true
      ..selectedProfileId = 'normal';
    addTearDown(controller.dispose);
    await mount(tester, controller);
    await tester.tap(find.byTooltip('New note'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('sync-v2-title')),
      'sensitive title',
    );
    await tester.enterText(
      find.byKey(const Key('sync-v2-body')),
      'sensitive body',
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(controller.backgroundCalled, isTrue);
    expect(find.text('sensitive title'), findsNothing);
    expect(find.text('sensitive body'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('New note'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('sync-v2-title')))
          .controller!
          .text,
      isEmpty,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('sync-v2-body')))
          .controller!
          .text,
      isEmpty,
    );
  });
  testWidgets('quick mode stays single paragraph after save and reopen', (
    tester,
  ) async {
    final controller = _Controller()
      ..registered = true
      ..selectedProfileId = 'normal'
      ..notes = [
        _note(
          'quick-note',
          title: 'Quick note',
          body: 'Original quick body',
          createdAt: DateTime.utc(2026),
          editorMode: NoteEditorMode.quick,
        ),
      ];
    addTearDown(controller.dispose);
    await mount(tester, controller);
    await openEditorFromList(tester, find.text('Quick note'));

    expect(find.byKey(const ValueKey('sync-v2-add-paragraph')), findsNothing);
    expect(find.byKey(const ValueKey('sync-v2-rich-move-up-0')), findsNothing);
    await tester.enterText(
      find.byKey(const Key('sync-v2-body')),
      'Updated quick body',
    );
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(controller.savedBlocks, isNull);

    controller.notes = [
      _note(
        'quick-note',
        title: 'Quick note',
        body: 'Updated quick body',
        createdAt: DateTime.utc(2026),
        editorMode: NoteEditorMode.quick,
      ),
    ];
    controller.notifyListeners();
    await tester.pumpAndSettle();
    await openEditorFromList(tester, find.text('Quick note'));
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('sync-v2-body')))
          .controller!
          .text,
      'Updated quick body',
    );
    expect(find.byKey(const ValueKey('sync-v2-add-paragraph')), findsNothing);
    expect(find.byKey(const ValueKey('sync-v2-rich-move-up-0')), findsNothing);
  });

  testWidgets(
    'rich picker inserts at the saved cursor and submits pending ref',
    (tester) async {
      final fileBytes = Completer<Uint8List>();
      final file = _DelayedPickedAttachment(fileBytes);
      final previousPicker = FilePickerPlatform.instance;
      FilePickerPlatform.instance = _ArchivePicker(files: [file]);
      addTearDown(() => FilePickerPlatform.instance = previousPicker);
      final controller = _Controller()
        ..registered = true
        ..selectedProfileId = 'normal'
        ..notes = [
          _note(
            'rich-picker-note',
            title: 'Rich picker note',
            body: 'abcdef',
            createdAt: DateTime.utc(2026),
            blocks: const [
              NoteBlock(type: NoteBlockType.paragraph, text: 'abcdef'),
            ],
          ),
        ];
      addTearDown(controller.dispose);
      await mount(tester, controller, displayStyle: null);
      await openEditorFromList(tester, find.text('Rich picker note'));
      final body = find.byKey(const Key('sync-v2-body'));
      await tester.tap(body);
      tester.widget<TextField>(body).controller!.selection =
          const TextSelection.collapsed(offset: 3);
      await tester.ensureVisible(find.text('Attach (up to 64 MiB)'));
      await tester.tap(find.text('Attach (up to 64 MiB)'));
      await tester.pump();
      expect(file.readStarted.isCompleted, isTrue);
      fileBytes.complete(Uint8List.fromList([1, 2, 3]));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(body).controller!.text, 'abc');
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('sync-v2-rich-paragraph-new-2')),
            )
            .controller!
            .text,
        'def',
      );
      expect(find.text('late-private.txt'), findsWidgets);

      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(controller.savedBlocks, hasLength(3));
      expect(controller.savedBlocks![0].text, 'abc');
      expect(
        controller.savedBlocks![1].attachment!.filePath,
        startsWith('v2pending:'),
      );
      expect(controller.savedBlocks![2].text, 'def');
      expect(controller.savedAddedFiles, hasLength(1));
      expect(controller.savedAddedFiles!.single.draftId, isNotEmpty);
      expect(controller.savedAddedFiles!.single.bytes, everyElement(0));
    },
  );

  testWidgets('rich picker accepts an unfocused paragraph selection', (
    tester,
  ) async {
    final fileBytes = Completer<Uint8List>();
    final file = _DelayedPickedAttachment(fileBytes);
    final previousPicker = FilePickerPlatform.instance;
    FilePickerPlatform.instance = _ArchivePicker(files: [file]);
    addTearDown(() => FilePickerPlatform.instance = previousPicker);
    final controller = _Controller()
      ..registered = true
      ..selectedProfileId = 'normal'
      ..notes = [
        _note(
          'unfocused-rich-picker-note',
          title: 'Unfocused picker note',
          body: 'Saved body',
          createdAt: DateTime.utc(2026),
          blocks: const [
            NoteBlock(type: NoteBlockType.paragraph, text: 'Saved body'),
          ],
        ),
      ];
    addTearDown(controller.dispose);
    await mount(tester, controller, displayStyle: null);
    await openEditorFromList(tester, find.text('Unfocused picker note'));
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('sync-v2-body')))
          .focusNode!
          .hasFocus,
      isFalse,
    );

    await tester.ensureVisible(find.text('Attach (up to 64 MiB)'));
    await tester.tap(find.text('Attach (up to 64 MiB)'));
    await tester.pump();
    fileBytes.complete(Uint8List.fromList([1, 2, 3]));
    await tester.pumpAndSettle();
    expect(find.text('late-private.txt'), findsWidgets);

    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(controller.savedBlocks, hasLength(3));
    expect(
      controller.savedBlocks![1].attachment!.filePath,
      startsWith('v2pending:'),
    );
  });

  testWidgets('rich picker rejects a changed selection while waiting', (
    tester,
  ) async {
    final fileBytes = Completer<Uint8List>();
    final file = _DelayedPickedAttachment(fileBytes);
    final previousPicker = FilePickerPlatform.instance;
    FilePickerPlatform.instance = _ArchivePicker(files: [file]);
    addTearDown(() => FilePickerPlatform.instance = previousPicker);
    final controller = _Controller()
      ..registered = true
      ..selectedProfileId = 'normal'
      ..notes = [
        _note(
          'changed-rich-picker-note',
          title: 'Changed picker note',
          body: 'Saved body',
          createdAt: DateTime.utc(2026),
          blocks: const [
            NoteBlock(type: NoteBlockType.paragraph, text: 'Saved body'),
          ],
        ),
      ];
    addTearDown(controller.dispose);
    await mount(tester, controller, displayStyle: null);
    await openEditorFromList(tester, find.text('Changed picker note'));
    await tester.ensureVisible(find.text('Attach (up to 64 MiB)'));
    await tester.tap(find.text('Attach (up to 64 MiB)'));
    await tester.pump();
    expect(file.readStarted.isCompleted, isTrue);

    final body = tester.widget<TextField>(
      find.byKey(const Key('sync-v2-body')),
    );
    body.controller!.selection = const TextSelection.collapsed(offset: 2);
    fileBytes.complete(Uint8List.fromList([1, 2, 3]));
    await tester.pumpAndSettle();
    expect(find.text('late-private.txt'), findsNothing);
    expect(
      find.byKey(const ValueKey('sync-v2-rich-paragraph-new-1')),
      findsNothing,
    );
  });

  testWidgets('late picker bytes are wiped after profile/session changes', (
    tester,
  ) async {
    final fileBytes = Completer<Uint8List>();
    final file = _DelayedPickedAttachment(fileBytes);
    final previousPicker = FilePickerPlatform.instance;
    FilePickerPlatform.instance = _ArchivePicker(files: [file]);
    addTearDown(() => FilePickerPlatform.instance = previousPicker);
    final controller = _Controller()
      ..registered = true
      ..selectedProfileId = 'normal';
    addTearDown(controller.dispose);
    await mount(tester, controller, displayStyle: 'simple');
    await tester.tap(find.byTooltip('New note'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Attach (up to 64 MiB)'));
    await tester.tap(find.text('Attach (up to 64 MiB)'));
    await tester.pump();
    expect(file.readStarted.isCompleted, isTrue);

    controller
      ..selectedProfileId = 'different-profile'
      ..notifyListeners();
    await tester.pump();
    final returnedBytes = Uint8List.fromList([9, 8, 7]);
    fileBytes.complete(returnedBytes);
    await tester.pumpAndSettle();
    expect(returnedBytes, everyElement(0));
    expect(find.text('late-private.txt'), findsNothing);
    expect(find.byKey(const Key('sync-v2-body')), findsNothing);
  });

  testWidgets('archive stays blocked through asynchronous attachment staging', (
    tester,
  ) async {
    final fileBytes = Completer<Uint8List>();
    final file = _DelayedPickedAttachment(fileBytes);
    final previousPicker = FilePickerPlatform.instance;
    final picker = _ArchivePicker(files: [file]);
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = previousPicker);
    final controller = _Controller()
      ..registered = true
      ..selectedProfileId = 'normal'
      ..notes = [
        _note(
          'archive-picker-note',
          title: 'Picker note',
          body: 'Saved body',
          createdAt: DateTime.utc(2026),
          blocks: const [
            NoteBlock(type: NoteBlockType.paragraph, text: 'Saved body'),
          ],
        ),
      ];
    addTearDown(controller.dispose);
    await mount(tester, controller, displayStyle: null);
    await openEditorFromList(tester, find.text('Picker note'));

    final archiveAction = find.byKey(const ValueKey('sync-v2-note-archive'));
    final staleArchiveCallback = tester
        .widget<IconButton>(archiveAction)
        .onPressed!;
    final attachAction = find.text('Attach (up to 64 MiB)');
    final attachButton = find.ancestor(
      of: attachAction,
      matching: find.byType(TextButton),
    );
    final staleAttachCallback = tester
        .widget<TextButton>(attachButton)
        .onPressed!;
    await tester.ensureVisible(attachAction);
    await tester.tap(attachAction);
    await tester.pump();
    expect(file.readStarted.isCompleted, isTrue);
    expect(picker.calls, 1);
    expect(tester.widget<TextButton>(attachButton).onPressed, isNull);

    staleAttachCallback();
    await tester.pump();
    expect(picker.calls, 1);
    expect(tester.widget<IconButton>(archiveAction).onPressed, isNull);

    staleArchiveCallback();
    await tester.pumpAndSettle();
    expect(controller.savedArchived, isNull);
    expect(find.byKey(const Key('sync-v2-title')), findsOneWidget);

    fileBytes.complete(Uint8List.fromList([1, 2, 3]));
    await tester.pumpAndSettle();
    expect(find.text('late-private.txt'), findsWidgets);
    expect(tester.widget<IconButton>(archiveAction).onPressed, isNull);
    expect(controller.savedArchived, isNull);
  });
  testWidgets('moved attachment removal can be undone before saving', (
    tester,
  ) async {
    final reference = _attachmentReference(label: 'photo');
    final controller = _Controller()
      ..registered = true
      ..selectedProfileId = 'normal'
      ..notes = [
        _note(
          'rich-delete-undo',
          title: 'Rich attachment note',
          body: 'First\n\nSecond',
          createdAt: DateTime.utc(2026),
          attachments: [reference],
          blocks: [
            const NoteBlock(type: NoteBlockType.paragraph, text: 'First'),
            const NoteBlock(type: NoteBlockType.paragraph, text: 'Second'),
            NoteBlock(
              type: NoteBlockType.photo,
              attachment: NoteAttachment(
                type: AttachmentType.photo,
                label: reference.label,
                filePath: 'v2attachment:${reference.id}',
              ),
            ),
          ],
        ),
      ];
    addTearDown(controller.dispose);
    await mount(tester, controller);
    await openEditorFromList(tester, find.text('Rich attachment note'));

    await tester.tap(find.byKey(const ValueKey('sync-v2-rich-move-up-2')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('sync-v2-rich-remove-attachment-2')),
    );
    await tester.pump();
    expect(find.byType(SyncV2RichBlocksEditor), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect(find.textContaining('photo'), findsNothing);

    tester.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed();
    await tester.pump();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(controller.savedRemovedAttachmentIds, isEmpty);
    expect(controller.savedBlocks!.map((block) => block.type), [
      NoteBlockType.paragraph,
      NoteBlockType.photo,
      NoteBlockType.paragraph,
    ]);
  });

  testWidgets('saving a removed block submits only its reference id', (
    tester,
  ) async {
    final reference = _attachmentReference(label: 'photo');
    final controller = _Controller()
      ..registered = true
      ..selectedProfileId = 'normal'
      ..notes = [
        _note(
          'rich-delete-save',
          title: 'Remove this block',
          body: 'Body',
          createdAt: DateTime.utc(2026),
          attachments: [reference],
          blocks: [
            const NoteBlock(type: NoteBlockType.paragraph, text: 'Body'),
            NoteBlock(
              type: NoteBlockType.photo,
              attachment: NoteAttachment(
                type: AttachmentType.photo,
                label: reference.label,
                filePath: 'v2attachment:${reference.id}',
              ),
            ),
          ],
        ),
      ];
    addTearDown(controller.dispose);
    await mount(tester, controller);
    await openEditorFromList(tester, find.text('Remove this block'));
    await tester.tap(
      find.byKey(const ValueKey('sync-v2-rich-remove-attachment-1')),
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(controller.savedRemovedAttachmentIds, [reference.id]);
    expect(controller.savedBlocks!.map((block) => block.type), [
      NoteBlockType.paragraph,
    ]);
  });

  testWidgets('profile switch clears an attachment deletion and its undo', (
    tester,
  ) async {
    final reference = _attachmentReference(label: 'photo');
    final controller = _Controller()
      ..registered = true
      ..selectedProfileId = 'normal'
      ..notes = [
        _note(
          'rich-delete-profile',
          title: 'Private transition note',
          body: 'Body',
          createdAt: DateTime.utc(2026),
          attachments: [reference],
          blocks: [
            const NoteBlock(type: NoteBlockType.paragraph, text: 'Body'),
            NoteBlock(
              type: NoteBlockType.photo,
              attachment: NoteAttachment(
                type: AttachmentType.photo,
                label: reference.label,
                filePath: 'v2attachment:${reference.id}',
              ),
            ),
          ],
        ),
      ];
    controller.availablePrivateProfiles.add(
      const SyncV2WorkspaceProfile('private', 'Private'),
    );
    addTearDown(controller.dispose);
    await mount(tester, controller);
    await openEditorFromList(tester, find.text('Private transition note'));
    await tester.tap(
      find.byKey(const ValueKey('sync-v2-rich-remove-attachment-1')),
    );
    await tester.pump();
    expect(find.textContaining('photo'), findsNothing);

    controller.selectedProfileId = 'private';
    controller.notes = [];
    controller.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.byType(SyncV2RichBlocksEditor), findsNothing);
    expect(find.text('Undo'), findsNothing);
    expect(find.byType(SyncV2RichBlocksEditor), findsNothing);
    expect(controller.savedRemovedAttachmentIds, isNull);
  });
  testWidgets('background lock dismisses attachment undo without its label', (
    tester,
  ) async {
    final reference = _attachmentReference(label: 'sensitive filename');
    final controller = _Controller()
      ..registered = true
      ..selectedProfileId = 'normal'
      ..notes = [
        _note(
          'rich-delete-lock',
          title: 'Locked attachment note',
          body: 'Body',
          createdAt: DateTime.utc(2026),
          attachments: [reference],
          blocks: [
            const NoteBlock(type: NoteBlockType.paragraph, text: 'Body'),
            NoteBlock(
              type: NoteBlockType.photo,
              attachment: NoteAttachment(
                type: AttachmentType.photo,
                label: reference.label,
                filePath: 'v2attachment:${reference.id}',
              ),
            ),
          ],
        ),
      ];
    addTearDown(controller.dispose);
    await mount(tester, controller);
    await openEditorFromList(tester, find.text('Locked attachment note'));
    await tester.tap(
      find.byKey(const ValueKey('sync-v2-rich-remove-attachment-1')),
    );
    await tester.pump();
    expect(find.textContaining('sensitive filename'), findsNothing);
    expect(find.text('Undo'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(controller.backgroundCalled, isTrue);
    expect(find.text('Undo'), findsNothing);
    expect(find.byType(SyncV2RichBlocksEditor), findsNothing);
    expect(controller.savedRemovedAttachmentIds, isNull);
  });
  testWidgets(
    'conflict requires explicit version selection and retains all heads',
    (tester) async {
      final clipboard = <String, Object?>{};
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard['text'] = (call.arguments as Map)['text'];
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final controller = _Controller()
        ..registered = true
        ..selectedProfileId = 'normal';
      addTearDown(controller.dispose);
      final note = NoteEntry(
        id: 'note',
        vaultId: 'normal',
        title: 'Conflict',
        body: 'first',
        createdAt: DateTime.utc(2026),
      );
      final original = SyncV2WorkspaceNote(
        note,
        SyncV2NoteSnapshot(
          versions: [
            for (final id in ['first', 'second'])
              SyncV2NoteVersion(
                change: SyncV2Change(
                  id: id,
                  profileId: 'normal',
                  noteId: 'note',
                  operation: SyncV2Operation.upsert,
                  parentIds: {},
                  payloadDigest: id,
                ),
                payloadAvailable: true,
                body: {
                  'type': 'note',
                  'note': note
                      .copyWith(
                        body: 'stale preview',
                        location: NoteLocation(
                          latitude: id == 'second' ? 35 : 34,
                          longitude: 139,
                          address: '$id location',
                        ),
                        blocks: [
                          NoteBlock(type: NoteBlockType.paragraph, text: id),
                        ],
                      )
                      .toJson(),
                  'attachments': [],
                },
              ),
            SyncV2NoteVersion(
              change: SyncV2Change(
                id: 'deleted',
                profileId: 'normal',
                noteId: 'note',
                operation: SyncV2Operation.delete,
                parentIds: {},
              ),
              payloadAvailable: true,
              body: null,
            ),
          ],
          pendingIds: {},
        ),
        [],
      );
      controller.notes = [original];
      await mount(tester, controller);
      await tester.tap(find.text('Conflict'));
      await tester.pumpAndSettle();
      expect(find.text('Deleted version'), findsOneWidget);
      expect(controller.chosenVersion, isNull);
      await tester.tap(find.text('Choose this version').at(1));
      await tester.pumpAndSettle();
      expect(find.text('second'), findsOneWidget);
      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('sync-v2-body')))
            .controller!
            .text,
        'second',
      );
      final copyButton = find.byKey(const ValueKey('sync-v2-copy-draft-text'));
      await tester.ensureVisible(copyButton);
      await tester.tap(copyButton);
      await tester.pumpAndSettle();
      expect(clipboard['text'], 'Conflict\n\nsecond\n\nsecond location');
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(controller.chosenVersion, 'second');
      expect(controller.savedOriginal!.headIds, {'first', 'second', 'deleted'});
    },
  );
  testWidgets('photo attachment opens a full zoomable image preview', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final attachment = _attachmentReference();
    final controller = _Controller()
      ..registered = true
      ..selectedProfileId = 'normal'
      ..previewBytes = _pixel()
      ..notes = [
        _note(
          'photo-note',
          title: 'Photo note',
          body: 'A picture',
          createdAt: DateTime.utc(2026),
          attachments: [attachment],
        ),
      ];
    final viewer = _AttachmentViewer();
    addTearDown(controller.dispose);
    await mount(
      tester,
      controller,
      displayStyle: 'simple',
      attachmentViewer: viewer,
    );
    await openEditorFromList(tester, find.text('Photo note'));
    await tester.pump(const Duration(milliseconds: 100));
    final inlineImage = find.byWidgetPredicate(
      (widget) => widget is SyncV2AttachmentImage && widget.thumbnail == false,
    );
    expect(inlineImage, findsOneWidget);
    await tester.ensureVisible(inlineImage);
    await tester.tap(inlineImage);
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey('sync-v2-attachment-image-data')),
      findsNWidgets(2),
    );
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(viewer.closeCalls, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('native viewer provider closes on background and clears bytes', (
    tester,
  ) async {
    final attachment = _attachmentReference(
      type: 'video',
      label: r'C:\private\clip.mov',
    );
    final controller = _Controller()
      ..registered = true
      ..selectedProfileId = 'normal'
      ..notes = [
        _note(
          'video-note',
          title: 'Video note',
          body: 'A clip',
          createdAt: DateTime.utc(2026),
          attachments: [attachment],
        ),
      ];
    final viewer = _AttachmentViewer()..openCompleter = Completer<void>();
    addTearDown(controller.dispose);
    await mount(
      tester,
      controller,
      displayStyle: 'simple',
      attachmentViewer: viewer,
    );
    await openEditorFromList(tester, find.text('Video note'));
    final attachmentLabel = find.text('clip.mov');
    await tester.ensureVisible(attachmentLabel);
    await tester.tap(attachmentLabel);
    await tester.pump();
    await tester.pump();
    expect(viewer.openCalls, 1);
    expect(viewer.openedLabel, 'clip.mov');
    final nativeBytes = viewer.openedBytes!;
    expect(nativeBytes, controller.previewBytes);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(viewer.closeCalls, greaterThan(0));
    expect(nativeBytes, everyElement(0));
    expect(controller.backgroundCalled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing preview invalidates a pending attachment read', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final attachment = _attachmentReference();
    final controller = _Controller()
      ..registered = true
      ..selectedProfileId = 'normal'
      ..notes = [
        _note(
          'pending-photo-note',
          title: 'Pending photo',
          body: 'Wait for preview',
          createdAt: DateTime.utc(2026),
          attachments: [attachment],
        ),
      ]
      ..previewBytesCompleter = Completer<Uint8List>()
      ..previewReadStarted = Completer<void>();
    addTearDown(controller.dispose);
    await mount(tester, controller, displayStyle: 'simple');
    final noteTitle = find.text('Pending photo');
    await tester.scrollUntilVisible(
      noteTitle,
      160,
      scrollable: find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(noteTitle);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await controller.previewReadStarted!.future;

    final returnedBytes = _pixel();
    await tester.tap(find.byKey(const ValueKey('sync-v2-preview-back')));
    await tester.pump();
    expect(find.byType(SyncV2AttachmentImage), findsNothing);
    controller.previewBytesCompleter!.complete(returnedBytes);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.latestPreviewIsActive!(), isFalse);
    expect(returnedBytes, everyElement(0));
    expect(controller.latestPreviewBytes, same(returnedBytes));
    expect(find.text('Pending photo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed 56px photo thumbnail keeps its fallback action usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final attachment = _attachmentReference();
    final controller = _Controller()
      ..registered = true
      ..selectedProfileId = 'normal'
      ..previewBytes = Uint8List.fromList([1, 2, 3])
      ..notes = [
        _note(
          'broken-photo-note',
          title: 'Broken photo',
          body: 'Unreadable image',
          createdAt: DateTime.utc(2026),
          attachments: [attachment],
        ),
      ];
    final viewer = _AttachmentViewer();
    addTearDown(controller.dispose);
    await mount(
      tester,
      controller,
      displayStyle: null,
      attachmentViewer: viewer,
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Open another way'), findsOneWidget);
    expect(controller.latestPreviewBytes, everyElement(0));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Open another way'));
    await tester.pumpAndSettle();
    expect(viewer.openCalls, 1);
    expect(tester.takeException(), isNull);
  });

  test('attachment save names use a safe basename', () {
    expect(syncV2AttachmentFileName(r'C:\secret\memo.txt'), 'memo.txt');
    expect(syncV2AttachmentFileName('../../memo.txt'), 'memo.txt');
    for (final label in ['', '.', '..', 'folder/']) {
      expect(syncV2AttachmentFileName(label), 'attachment.bin');
    }
  });
  testWidgets(
    'background preserves prepared codes and requires original password again',
    (tester) async {
      final controller = _Controller();
      addTearDown(controller.dispose);
      await mount(tester, controller);
      await tester.tap(find.text('Create workspace'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'original-password');
      await tester.enterText(find.byType(TextField).at(1), 'original-password');
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('SYNC-secret-code'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      // A rapid resume must not turn the interrupted dialog into Cancel.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('SYNC-secret-code'), findsNothing);
      expect(controller.cancellations, 0);
      expect(controller.confirmations, 0);
      await tester.tap(find.text('Continue setup'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'original-password');
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('SYNC-secret-code'), findsOneWidget);
      expect(find.text('ADMIN-secret-code'), findsOneWidget);
      expect(controller.passwords, ['original-password', 'original-password']);
      expect(controller.confirmations, 0);
      await tester.tap(find.byType(CheckboxListTile).at(0));
      await tester.pump();
      await tester.tap(find.byType(CheckboxListTile).at(1));
      await tester.pump();
      await tester.tap(find.text('Register in cloud'));
      await tester.pumpAndSettle();
      expect(controller.confirmations, 1);
    },
  );
  testWidgets('prepared setup can be cancelled without the original password', (
    tester,
  ) async {
    final controller = _Controller()..prepared = true;
    addTearDown(controller.dispose);
    await mount(tester, controller);
    await tester.tap(find.text('Cancel prepared setup'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(controller.cancellations, 0);
    await tester.tap(find.text('Confirm and continue'));
    await tester.pumpAndSettle();
    expect(controller.cancellations, 1);
    expect(controller.passwords, isEmpty);
    expect(find.text('Create workspace'), findsOneWidget);
  });
}
