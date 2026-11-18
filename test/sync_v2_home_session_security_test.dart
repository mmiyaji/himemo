import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/app/app.dart';
import 'package:himemo/app/app_flavor.dart';
import 'package:himemo/features/home/presentation/home_providers.dart';
import 'package:himemo/features/security/data/authentication_throttle.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:himemo/features/sync/data/sync_v2_enrollment_store.dart';
import 'package:himemo/features/sync/data/sync_v2_generation_registration.dart';
import 'package:himemo/features/sync/data/sync_v2_header_codec.dart';
import 'package:himemo/features/sync/data/sync_v2_inbox.dart';
import 'package:himemo/features/sync/data/sync_v2_note_repository.dart';
import 'package:himemo/features/sync/data/sync_v2_payload_codec.dart';
import 'package:himemo/features/sync/presentation/sync_v2_workspace.dart';
import 'package:himemo/features/sync/testing/sync_v2_local_preview.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'locking an unopened profile cancels an in-flight passcode unlock',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      harness.pauseUnlock();
      final unlocking = harness.container
          .read(privateProfileUnlockControllerProvider.notifier)
          .unlockWithPassword('5678');
      await harness.store.entered.future;
      expect(
        harness.container.read(unlockedPrivateProfileVaultIdProvider),
        isNull,
      );
      harness.container
          .read(unlockedPrivateProfileVaultIdProvider.notifier)
          .lock();
      harness.store.release.complete();
      expect(await unlocking, isNull);
      harness.expectLocked();
    },
  );

  test(
    'admin logout cancels a passcode unlock before admin state is true',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      harness.pauseUnlock();
      final unlocking = harness.container
          .read(adminModeSessionControllerProvider.notifier)
          .unlockWithAdminPassword('1234');
      final rejected = expectLater(
        unlocking,
        throwsA(isA<SyncV2WorkspaceException>()),
      );
      await harness.store.entered.future;
      expect(
        harness.container.read(adminModeSessionControllerProvider),
        isFalse,
      );
      harness.container
          .read(adminModeSessionControllerProvider.notifier)
          .lock();
      harness.store.release.complete();
      await rejected;
      harness.expectLocked();
    },
  );

  test(
    'an older cancelled unlock does not revoke a newer private session',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      harness.pauseUnlock();
      final controller = harness.container.read(
        privateProfileUnlockControllerProvider.notifier,
      );
      final older = controller.unlockWithPassword('5678');
      await harness.store.entered.future;
      final newer = controller.unlockWithPassword('5678');
      harness.store.release.complete();
      expect(await older, isNull);
      expect(await newer, isNotNull);
      expect(harness.workspace.adminUnlocked, isFalse);
      expect(
        harness.container.read(unlockedPrivateProfileVaultIdProvider),
        harness.privateId,
      );
      expect(
        harness.workspace.noteStoreSession!.profiles,
        contains(harness.privateId),
      );
      expect(
        harness.container
            .read(notesControllerProvider)
            .any((note) => note.title == 'Secret'),
        isTrue,
      );
    },
  );

  test(
    'a lock also invalidates an admin unlock waiting in the workspace queue',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      harness.holdSync = true;
      final syncing = harness.workspace.syncNow();
      await harness.syncEntered.future;
      final unlocking = harness.workspace.unlockAdmin('1234');
      final rejected = expectLater(
        unlocking,
        throwsA(isA<SyncV2WorkspaceException>()),
      );
      harness.workspace.lockPrivate();
      harness.syncRelease.complete();
      await syncing;
      await rejected;
      harness.expectLocked();
    },
  );

  testWidgets('app relock revokes a pending unlock with no active UI session', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final temporary = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('himemo-session-security-'),
    ))!;
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (call) async => temporary.path);
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProvider, null);
      await temporary.delete(recursive: true);
    });
    final harness = (await tester.runAsync(
      () => _Harness.create(appLock: true),
    ))!;
    addTearDown(harness.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: const HiMemoApp(flavor: AppFlavor.development),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();
    harness.pauseUnlock();
    late Future<UnlockProfileResult?> unlocking;
    await tester.runAsync(() async {
      unlocking = harness.container
          .read(privateProfileUnlockControllerProvider.notifier)
          .unlockWithPassword('5678');
      await harness.store.entered.future;
    });
    final revision = harness.workspace.privateSessionRevision;
    expect(
      harness.container.read(unlockedPrivateProfileVaultIdProvider),
      isNull,
    );
    expect(harness.container.read(adminModeSessionControllerProvider), isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 50));
    expect(harness.workspace.privateSessionRevision, greaterThan(revision));
    await tester.runAsync(() async {
      harness.store.release.complete();
      expect(await unlocking, isNull);
    });
    harness.expectLocked();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _GateStore extends MemorySecureKeyValueStore {
  String? blockedKey;
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<String?> read(String key) async {
    if (key == blockedKey) {
      blockedKey = null;
      entered.complete();
      await release.future;
    }
    return super.read(key);
  }
}

class _Harness {
  final store = _GateStore();
  final syncEntered = Completer<void>();
  final syncRelease = Completer<void>();
  bool holdSync = false;
  late final SyncV2WorkspaceController workspace;
  late final ProviderContainer container;
  late final String privateId;

  static Future<_Harness> create({bool appLock = false}) async {
    SharedPreferences.setMockInitialValues({
      'app.onboarding_completed': true,
      'app.onboarding_completed_version': 2,
      'settings.locale': 'english',
      'settings.app_lock_enabled': appLock,
      'settings.app_lock_relock_delay': 'immediate',
    });
    configureFlavor(AppFlavor.development);
    final harness = _Harness();
    final encryption = EncryptionService();
    final headers = SyncV2HeaderCodec(encryption);
    final inbox = SyncV2Inbox(NativeDatabase.memory(), headers);
    final registration = LocalPreviewRegistration(inbox);
    final enrollments = SyncV2EnrollmentStore(harness.store);
    harness.workspace = SyncV2WorkspaceController(
      inbox: inbox,
      repository: SyncV2NoteRepository(
        inbox,
        headers,
        SyncV2PayloadCodec(encryption),
      ),
      store: harness.store,
      enrollments: enrollments,
      registrationTransport: registration,
      registrationFactory: (_) =>
          SyncV2GenerationRegistration(registration, enrollments),
      syncOperation: () async {
        if (harness.holdSync) {
          harness.syncEntered.complete();
          await harness.syncRelease.future;
        }
        return (
          headersStaged: false,
          hasMoreHeaders: false,
          downloadedPayloads: 0,
          publishedChanges: 0,
          errors: <String>[],
        );
      },
      supported: true,
      automaticSync: false,
    );
    await harness.workspace.initialize();
    await harness.workspace.prepareNew('1234');
    await harness.workspace.confirmSetup();
    await harness.workspace.createProfile('Private', '5678');
    harness.privateId = harness.workspace.selectedProfileId!;
    await harness.workspace.saveNote(
      title: 'Secret',
      body: 'Private plaintext',
    );
    harness.workspace.lockPrivate();
    harness.container = ProviderContainer(
      overrides: [
        syncV2WorkspaceProvider.overrideWithValue(harness.workspace),
        secureKeyValueStoreProvider.overrideWithValue(harness.store),
        unseenReleaseNoteProvider.overrideWith((ref) async => null),
        deviceAuthGatewayProvider.overrideWithValue(_DeviceAuth()),
      ],
    );
    await harness.container
        .read(notesControllerProvider.notifier)
        .restoreCompleted;
    return harness;
  }

  void pauseUnlock() {
    store.blockedKey = syncV2UnlockAttemptsKey(workspace.generationId!);
  }

  void expectLocked() {
    expect(workspace.adminUnlocked, isFalse);
    expect(workspace.noteStoreSession!.profiles, isNot(contains(privateId)));
    expect(container.read(adminModeSessionControllerProvider), isFalse);
    expect(container.read(unlockedPrivateProfileVaultIdProvider), isNull);
    expect(
      container
          .read(notesControllerProvider)
          .any((note) => note.title == 'Secret'),
      isFalse,
    );
  }

  void dispose() {
    container.dispose();
    workspace.dispose();
  }
}

class _DeviceAuth implements DeviceAuthGateway {
  @override
  Future<bool> authenticate({
    required String reason,
    bool biometricOnly = false,
  }) async => true;

  @override
  Future<DeviceAuthState> checkAvailability() async => const DeviceAuthState(
    availability: DeviceAuthAvailability.available,
    methods: ['Device credential'],
  );
}
