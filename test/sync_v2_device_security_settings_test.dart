import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:himemo/features/sync/data/sync_v2_enrollment_store.dart';
import 'package:himemo/features/sync/data/sync_v2_generation_registration.dart';
import 'package:himemo/features/sync/data/sync_v2_header_codec.dart';
import 'package:himemo/features/sync/data/sync_v2_inbox.dart';
import 'package:himemo/features/sync/data/sync_v2_note_repository.dart';
import 'package:himemo/features/sync/data/sync_v2_payload_codec.dart';
import 'package:himemo/features/sync/presentation/sync_v2_device_security_settings.dart';
import 'package:himemo/features/sync/presentation/sync_v2_pairing_dialogs.dart';
import 'package:himemo/features/sync/presentation/sync_v2_workspace.dart';
import 'package:himemo/features/sync/testing/sync_v2_local_preview.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SyncV2WorkspaceController> workspace({bool register = true}) async {
  SharedPreferences.setMockInitialValues({});
  final encryption = EncryptionService();
  final store = MemorySecureKeyValueStore();
  final headers = SyncV2HeaderCodec(encryption);
  final inbox = SyncV2Inbox(NativeDatabase.memory(), headers);
  final registration = LocalPreviewRegistration(inbox);
  final enrollments = SyncV2EnrollmentStore(store);
  final controller = SyncV2WorkspaceController(
    inbox: inbox,
    repository: SyncV2NoteRepository(
      inbox,
      headers,
      SyncV2PayloadCodec(encryption),
    ),
    store: store,
    enrollments: enrollments,
    registrationTransport: registration,
    registrationFactory: (_) =>
        SyncV2GenerationRegistration(registration, enrollments),
    syncOperation: () async => (
      headersStaged: false,
      hasMoreHeaders: false,
      downloadedPayloads: 0,
      publishedChanges: 0,
      errors: <String>[],
    ),
    supported: true,
    automaticSync: false,
  );
  await controller.initialize();
  if (register) {
    await controller.prepareNew('1234');
    await controller.confirmSetup();
  }
  return controller;
}

void main() {
  testWidgets(
    'first-time setup stays in settings and requires recovery acknowledgement',
    (tester) async {
      final controller = (await tester.runAsync(
        () => workspace(register: false),
      ))!;
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            syncV2WorkspaceProvider.overrideWithValue(controller),
            syncV2RecoveryFileWriterProvider.overrideWithValue(
              (bytes, title) async => true,
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: SyncV2DeviceSecuritySettings(),
              ),
            ),
          ),
        ),
      );
      Future<void> begin() async {
        await tester.tap(find.text('First time: set up iCloud sync'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, '1234');
        await tester.enterText(find.byType(TextField).last, '1234');
        await tester.runAsync(() async {
          await tester.tap(find.text('Continue'));
          await tester.pump();
          for (var i = 0; i < 100 && !controller.hasPreparedSetup; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
        });
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          for (var i = 0; i < 200 && !controller.hasPreparedSetup; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
        });
        await tester.pumpAndSettle();
      }

      await begin();

      expect(find.text('Keep your recovery file'), findsOneWidget);
      expect(controller.registered, isFalse);
      expect(controller.hasPreparedSetup, isTrue);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Start iCloud sync'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        for (var i = 0; i < 100 && controller.hasPreparedSetup; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pumpAndSettle();
      expect(controller.hasPreparedSetup, isFalse);
      expect(controller.registered, isFalse);
      await begin();
      expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile))
            .onChanged,
        isNull,
      );
      await tester.tap(find.text('Save recovery file'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Start iCloud sync'));
        for (var i = 0; i < 100 && !controller.registered; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pumpAndSettle();
      expect(controller.registered, isTrue);
      expect(find.text('Automatic iCloud sync'), findsOneWidget);
      expect(find.text('First time: set up iCloud sync'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'combined pairing is primary and sensitive QR closes on background',
    (tester) async {
      final controller = (await tester.runAsync(workspace))!;
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [syncV2WorkspaceProvider.overrideWithValue(controller)],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: SyncV2DeviceSecuritySettings(),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Administrator passcode'), findsOneWidget);
      expect(find.text('Sync now'), findsOneWidget);
      expect(find.text('Automatic iCloud sync'), findsOneWidget);
      expect(find.text('Change unlock method'), findsOneWidget);
      expect(find.text('Detailed sync'), findsNothing);
      expect(find.text('Authenticate administrator'), findsNothing);
      expect(find.text('Use biometrics'), findsNothing);
      await tester.runAsync(() => controller.syncNow());
      await tester.pumpAndSettle();
      expect(find.textContaining('Last synced'), findsOneWidget);
      expect(find.text('Show pairing QR'), findsOneWidget);
      expect(find.text('Save recovery file'), findsOneWidget);
      expect(find.text('Show sync-only QR'), findsNothing);
      await tester.runAsync(() async {
        await tester.tap(find.text('Show pairing QR'));
      });
      await tester.pumpAndSettle();
      expect(find.byType(SyncV2PairingQrDialog), findsOneWidget);
      final dialog = tester.widget<SyncV2PairingQrDialog>(
        find.byType(SyncV2PairingQrDialog),
      );
      expect(dialog.device, isTrue);
      expect(dialog.administrator, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(find.byType(SyncV2PairingQrDialog), findsNothing);
      expect(controller.adminUnlocked, isFalse);
      await tester.runAsync(() async {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await controller.resume();
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'sync-only QR stays behind advanced settings and passcodes are confirmed',
    (tester) async {
      final controller = (await tester.runAsync(workspace))!;
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [syncV2WorkspaceProvider.overrideWithValue(controller)],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: SyncV2DeviceSecuritySettings(),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Change unlock method'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set or change administrator passcode'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '123');
      await tester.enterText(find.byType(TextField).last, '123');
      await tester.tap(find.text('Continue'));
      await tester.pump();
      expect(
        find.text('Enter matching passcodes of at least four characters.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add a device without administrator access'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Show sync-only QR'));
      await tester.runAsync(() async {
        await tester.tap(find.text('Show sync-only QR'));
      });
      await tester.pumpAndSettle();
      final dialog = tester.widget<SyncV2PairingQrDialog>(
        find.byType(SyncV2PairingQrDialog),
      );
      expect(dialog.device, isTrue);
      expect(dialog.administrator, isFalse);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
