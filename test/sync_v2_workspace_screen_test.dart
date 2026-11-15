import 'dart:async';

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
  _Controller()
    : super(
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
        automaticSync: false,
      );
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

  bool backgroundCalled = false;
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
  ];
  @override
  void background() {
    backgroundCalled = true;
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
