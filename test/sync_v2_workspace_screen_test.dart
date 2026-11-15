import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/sync/data/sync_v2_history.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:himemo/features/sync/data/sync_v2_enrollment_store.dart';
import 'package:himemo/features/sync/data/sync_v2_generation_registration.dart';
import 'package:himemo/features/sync/data/sync_v2_inbox.dart';
import 'package:himemo/features/sync/data/sync_v2_note_repository.dart';
import 'package:himemo/features/sync/presentation/sync_v2_workspace.dart';
import 'package:himemo/features/sync/presentation/sync_v2_workspace_screen.dart';
import 'package:himemo/features/sync/presentation/sync_v2_privacy.dart';

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

class _ArchivePicker extends FilePickerPlatform {
  _ArchivePicker({this.onPickerCalled});

  final Future<void> Function()? onPickerCalled;

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
    await onPickerCalled?.call();
    return [_PickedArchive()];
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
  @override
  Future<void> saveNote({
    SyncV2WorkspaceNote? original,
    String? selectedVersionId,
    required String title,
    required String body,
    List<SyncV2PendingAttachment> addedFiles = const [],
    List<String> removedAttachmentIds = const [],
  }) async {
    chosenVersion = selectedVersionId;
    savedOriginal = original;
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
    if (!fakeDisposed) notifyListeners();
  }

  @override
  Future<void> resume() async {}
}

void main() {
  testWidgets(
    'workspace lifetime enables native privacy protection independently of legacy profiles',
    (tester) async {
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
  Future<void> mount(WidgetTester tester, _Controller controller) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [syncV2WorkspaceProvider.overrideWithValue(controller)],
        child: const MaterialApp(home: SyncV2WorkspaceScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

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
  testWidgets(
    'conflict requires explicit version selection and retains all heads',
    (tester) async {
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
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('sync-v2-body')))
            .controller!
            .text,
        'second',
      );
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(controller.chosenVersion, 'second');
      expect(controller.savedOriginal!.headIds, {'first', 'second', 'deleted'});
    },
  );
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
