import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:himemo/features/security/data/sync_v2_biometric_key_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:himemo/features/security/data/sync_v2_profile_keys.dart';
import 'package:himemo/features/sync/data/sync_v2_enrollment_store.dart';
import 'package:himemo/features/sync/data/sync_v2_generation_registration.dart';
import 'package:himemo/features/sync/data/sync_v2_header_codec.dart';
import 'package:himemo/features/sync/data/sync_v2_history.dart';
import 'package:himemo/features/sync/data/sync_v2_icloud_session.dart';
import 'package:himemo/features/sync/data/sync_v2_inbox.dart';
import 'package:himemo/features/sync/data/sync_v2_note_repository.dart';
import 'package:himemo/features/sync/data/sync_v2_payload_codec.dart';
import 'package:himemo/features/sync/data/sync_v2_publisher.dart';
import 'package:himemo/features/sync/data/sync_v2_receiver.dart';
import 'package:himemo/features/sync/data/sync_v2_pairing_code.dart';
import 'package:himemo/features/sync/data/sync_v2_device_transfer.dart';
import 'package:himemo/features/sync/presentation/sync_v2_workspace.dart';

class _Cloud
    implements
        SyncV2GenerationRegistrationTransport,
        SyncV2WriteTransport,
        SyncV2ReadTransport {
  String? proof;
  String account = 'account';
  bool offline = false;
  bool rejectPreparation = false;
  int registryWrites = 0;
  final records = <SyncV2Publication>[];
  @override
  Future<String> readCurrentAccountId() async {
    if (offline) throw StateError('offline');
    return account;
  }

  @override
  Future<String?> readRegistration() async {
    if (offline) throw StateError('offline');
    return proof;
  }

  @override
  Future<void> prepareGeneration(String generationId) async {
    if (rejectPreparation) throw StateError('interrupted');
    registryWrites++;
  }

  @override
  Future<void> publishRegistration(String encryptedProof) async {
    registryWrites++;
    if (proof != null && proof != encryptedProof) throw StateError('collision');
    proof = encryptedProof;
  }

  @override
  Future<void> publish({
    required String generationId,
    required SyncV2Publication publication,
  }) async {
    if (offline) throw StateError('offline');
    if (records.any((r) => r.id == publication.id)) return;
    records.add(publication);
  }

  @override
  Future<SyncV2RemoteHeader> fetchHeader({
    required String generationId,
    required String recordId,
  }) async {
    final record = records.singleWhere((r) => r.id == recordId);
    return (id: record.id, encryptedHeader: record.encryptedHeader);
  }

  @override
  Future<SyncV2RemotePage> fetchHeaders({
    required String generationId,
    required String? cursor,
    required int limit,
  }) async {
    if (offline) throw StateError('offline');
    final start = int.parse(cursor ?? '0');
    final page = records.skip(start).take(limit).toList();
    return SyncV2RemotePage(
      nextCursor: '${start + page.length}',
      hasMore: start + page.length < records.length,
      headers: [
        for (final record in page)
          (id: record.id, encryptedHeader: record.encryptedHeader),
      ],
    );
  }

  @override
  Future<Uint8List> fetchPayload({
    required String generationId,
    required String recordId,
  }) async => Uint8List.fromList(
    records.singleWhere((r) => r.id == recordId).encryptedPayload!,
  );
}

class _Store extends SecureKeyValueStore {
  final backing = MemorySecureKeyValueStore();
  Completer<void>? unlockEntered, unlockRelease;
  Completer<void>? restoreEntered, restoreRelease;
  Completer<void>? deviceAdminReadEntered, deviceAdminReadRelease;
  Completer<void>? enrollmentReadEntered, enrollmentReadRelease;
  bool failDeviceAdminWrites = false;
  @override
  Future<String?> read(String key) async {
    if (key == 'security.icloud_sync_v2.verified_proof.v1' &&
        restoreRelease != null) {
      restoreEntered!.complete();
      await restoreRelease!.future;
      restoreRelease = null;
    }
    if (key.startsWith('security.sync_v2.device_admin.') &&
        deviceAdminReadRelease != null) {
      deviceAdminReadEntered!.complete();
      await deviceAdminReadRelease!.future;
      deviceAdminReadRelease = null;
    }
    if (key == 'security.icloud_sync_v2.enrollment.v1' &&
        enrollmentReadRelease != null) {
      enrollmentReadEntered!.complete();
      await enrollmentReadRelease!.future;
      enrollmentReadRelease = null;
    }
    if (key.startsWith('sync.v2.unlock.') &&
        key.endsWith('.attempts') &&
        unlockRelease != null) {
      unlockEntered!.complete();
      await unlockRelease!.future;
      unlockRelease = null;
    }
    return backing.read(key);
  }

  @override
  Future<void> write(String key, String value) {
    if (failDeviceAdminWrites &&
        key.startsWith('security.sync_v2.device_admin.')) {
      throw StateError('device admin store unavailable');
    }
    return backing.write(key, value);
  }

  bool failDeletes = false;
  @override
  Future<void> delete(String key) {
    if (failDeletes) throw StateError('key store unavailable');
    return backing.delete(key);
  }
}

class _Biometrics implements SyncV2BiometricKeyStore {
  final keys = <String, List<int>>{};
  bool available = true, cancel = false;
  Completer<void>? entered, release;
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<void> save(String generationId, SecretKey key) async {
    if (cancel) throw PlatformException(code: 'cancelled');
    keys[generationId] = List.of(await key.extractBytes());
  }

  @override
  Future<SecretKey?> read(String generationId) async {
    if (release != null) {
      entered!.complete();
      await release!.future;
      release = null;
    }
    if (cancel) throw PlatformException(code: 'cancelled');
    return keys[generationId] == null ? null : SecretKey(keys[generationId]!);
  }

  @override
  Future<void> delete(String generationId) async => keys.remove(generationId);
}

class _HeldBatchRepository extends SyncV2NoteRepository {
  // The superclass field-formal parameter names are library-private.
  // ignore: use_super_parameters
  _HeldBatchRepository(
    SyncV2Inbox inbox,
    SyncV2HeaderCodec headers,
    SyncV2PayloadCodec payloads,
  ) : super(inbox, headers, payloads);

  Completer<void>? entered;
  Completer<void>? release;

  @override
  Future<void> saveNewBatch({
    required String generationId,
    required String profileId,
    required SecretKey syncKey,
    required SyncV2UnlockedProfileKey profileKey,
    void Function()? checkActive,
    required List<({String noteId, String changeId, Map<String, Object?> body})>
    notes,
  }) async {
    await super.saveNewBatch(
      generationId: generationId,
      profileId: profileId,
      syncKey: syncKey,
      profileKey: profileKey,
      checkActive: checkActive,
      notes: notes,
    );
    final gate = release;
    if (gate != null) {
      entered!.complete();
      await gate.future;
      release = null;
      checkActive?.call();
    }
  }
}

class _ProjectedNotesRepository extends SyncV2NoteRepository {
  _ProjectedNotesRepository(super.inbox, super.headers, super.payloads);

  Map<String, SyncV2NoteSnapshot>? projection;
  bool failRead = false;
  Object? catalogFailure;

  @override
  Future<Map<String, SyncV2NoteSnapshot>> readProfile({
    required String generationId,
    required String profileId,
    required SecretKey syncKey,
    SyncV2UnlockedProfileKey? profileKey,
    String? noteIdPrefix,
  }) async {
    if (noteIdPrefix == 'profile_' && catalogFailure != null) {
      throw catalogFailure!;
    }
    if (failRead) throw StateError('profile read failed');
    return projection ??
        super.readProfile(
          generationId: generationId,
          profileId: profileId,
          syncKey: syncKey,
          profileKey: profileKey,
          noteIdPrefix: noteIdPrefix,
        );
  }
}

class _Device {
  _Device(
    this.cloud, {
    _Store? sharedStore,
    _Biometrics? biometrics,
    bool Function()? settingsAdminAuthenticated,
    SyncV2NoteRepository Function(
      SyncV2Inbox,
      SyncV2HeaderCodec,
      SyncV2PayloadCodec,
    )?
    repositoryFactory,
  }) : store = sharedStore ?? _Store() {
    final encryption = EncryptionService();
    final headers = SyncV2HeaderCodec(encryption);
    inbox = SyncV2Inbox(NativeDatabase.memory(), headers);
    final payloads = SyncV2PayloadCodec(encryption);
    final repository =
        repositoryFactory?.call(inbox, headers, payloads) ??
        SyncV2NoteRepository(inbox, headers, payloads);
    enrollment = SyncV2EnrollmentStore(store);
    workspace = SyncV2WorkspaceController(
      inbox: inbox,
      repository: repository,
      store: store,
      enrollments: enrollment,
      registrationTransport: cloud,
      registrationFactory: (_) =>
          SyncV2GenerationRegistration(cloud, enrollment),
      syncOperation: sync,
      supported: true,
      biometricStore: biometrics ?? _Biometrics(),
      settingsAdminAuthenticated: settingsAdminAuthenticated,
      automaticSync: false,
    );
  }
  final _Cloud cloud;
  final _Store store;
  late final SyncV2Inbox inbox;
  late final SyncV2EnrollmentStore enrollment;
  late final SyncV2WorkspaceController workspace;
  Completer<void>? syncEntered, syncRelease;
  Future<SyncV2ICloudProgress> sync() async {
    if (syncRelease != null) {
      syncEntered!.complete();
      await syncRelease!.future;
      syncRelease = null;
    }
    final local = (await enrollment.readForAccount('account'))!;
    try {
      final published = await SyncV2Publisher(cloud, inbox).publishPage(
        generationId: local.generationId,
        limit: 50,
        stopOnQuarantine: true,
      );
      final receiver = SyncV2Receiver(cloud, inbox);
      final page = await receiver.pullPage(
        generationId: local.generationId,
        syncKey: local.syncKey,
        limit: 50,
      );
      final downloaded = await receiver.pullPendingPayloads(
        generationId: local.generationId,
        syncKey: local.syncKey,
        limit: 50,
      );
      return (
        headersStaged: page.staged,
        hasMoreHeaders: page.hasMore,
        publishedChanges: published,
        downloadedPayloads: downloaded,
        errors: <String>[],
      );
    } finally {
      local.syncKey.destroy();
    }
  }
}

class _UnavailableWorkspaceNote extends SyncV2WorkspaceNote {
  _UnavailableWorkspaceNote(SyncV2WorkspaceNote source)
    : super(source.note, source.snapshot, source.attachments);

  @override
  bool get ready => false;
}

Future<void> _seedNativeNote(_Device device, NoteEntry note) async {
  final workspace = device.workspace;
  final session = workspace.noteStoreSession!;
  final profileId = workspace.selectedProfileId!;
  await workspace.repository.save(
    generationId: session.generationId,
    profileId: profileId,
    noteId: note.id,
    changeId: 'seed_${note.id}',
    expectedHeadIds: {},
    body: {
      'type': 'note',
      'note': note.copyWith(vaultId: profileId).toJson(),
      'attachments': [],
    },
    syncKey: session.syncKey,
    profileKey: session.profiles[profileId]!,
  );
  await workspace.selectProfile(profileId);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('quarantines one corrupt note without exposing its plaintext or failing the profile', () async {
    final cloud = _Cloud();
    _ProjectedNotesRepository? repository;
    final device = _Device(
      cloud,
      repositoryFactory: (inbox, headers, payloads) =>
          repository = _ProjectedNotesRepository(inbox, headers, payloads),
    );
    addTearDown(device.workspace.dispose);
    final c = device.workspace;
    await c.initialize();
    await c.prepareNewBiometric();
    await c.confirmSetup();
    final profileId = c.selectedProfileId!;

    SyncV2NoteSnapshot snapshot(String noteId, Map<String, Object?> body) {
      final change = SyncV2Change(
        id: 'change-$noteId',
        profileId: profileId,
        noteId: noteId,
        operation: SyncV2Operation.upsert,
        parentIds: const {},
        payloadDigest: 'digest-$noteId',
      );
      return SyncV2NoteSnapshot(
        versions: [
          SyncV2NoteVersion(change: change, payloadAvailable: true, body: body),
        ],
        pendingIds: const {},
      );
    }

    final corruptId = 'note_corrupt';
    final corruptNote = NoteEntry(
      id: corruptId,
      vaultId: profileId,
      title: 'private title must be hidden',
      body: 'private body must be hidden',
      createdAt: DateTime.utc(2025),
    );
    final corruptBody = <String, Object?>{
      'type': 'note',
      'note': corruptNote.toJson(),
      'attachments': ['malformed reference must be hidden'],
    };
    final goodId = 'note_good';
    final goodNote = NoteEntry(
      id: goodId,
      vaultId: profileId,
      title: 'Healthy note',
      body: 'Healthy body',
      createdAt: DateTime.utc(2026),
    );
    final corruptSnapshot = snapshot(corruptId, corruptBody);
    repository!.projection = {
      corruptId: corruptSnapshot,
      goodId: snapshot(goodId, {'type': 'note', 'note': goodNote.toJson()}),
    };

    await c.selectProfile(profileId);

    expect(c.notes, hasLength(2));
    final quarantined = c.notes.singleWhere(
      (note) => note.note.id == corruptId,
    );
    expect(quarantined.isCorrupt, isTrue);
    expect(quarantined.readOnly, isTrue);
    expect(quarantined.ready, isFalse);
    expect(quarantined.note.title, isEmpty);
    expect(quarantined.note.body, isEmpty);
    expect(quarantined.attachments, isEmpty);
    expect(quarantined.snapshot.versions.single.body, isNull);
    expect(quarantined.snapshot.headIds, {'change-$corruptId'});
    expect(
      c.notes.singleWhere((note) => note.note.id == goodId).note.title,
      'Healthy note',
    );
    expect(corruptSnapshot.versions.single.body, same(corruptBody));
    expect(corruptBody['note'], equals(corruptNote.toJson()));
    await expectLater(
      c.updateTag('work'),
      throwsA(
        isA<SyncV2WorkspaceException>().having(
          (e) => e.code,
          'code',
          'tag_corrupt',
        ),
      ),
    );
    await expectLater(
      c.deleteNote(quarantined),
      throwsA(
        isA<SyncV2WorkspaceException>().having(
          (error) => error.code,
          'code',
          'conflict',
        ),
      ),
    );
    expect(corruptSnapshot.versions.single.body, same(corruptBody));

    repository!.failRead = true;
    await expectLater(
      c.selectProfile(profileId),
      throwsA(
        isA<SyncV2WorkspaceException>().having(
          (failure) => failure.code,
          'code',
          'operation_failed',
        ),
      ),
    );
  });

  test(
    'generated recovery codes pair devices through role-specific QR codes',
    () async {
      final cloud = _Cloud();
      final first = _Device(cloud);
      addTearDown(first.workspace.dispose);
      await first.workspace.initialize();
      final codes = await first.workspace.prepareNewBiometric();
      await first.workspace.confirmSetup();

      await first.workspace.createProfile('QR profile', '5678');
      await first.workspace.saveNote(
        title: 'QR paired private note',
        body: 'available only after administrator recovery',
      );
      await first.workspace.syncNow();

      final second = _Device(cloud);
      addTearDown(second.workspace.dispose);
      await second.workspace.initialize();
      final syncQr = SyncV2PairingCode.encodeQr(
        codes.syncCode,
        administrator: false,
      );
      await second.workspace.recover(
        SyncV2PairingCode.decodeQr(syncQr, administrator: false),
      );
      expect(second.workspace.registered, isTrue);
      expect(second.workspace.adminUnlocked, isFalse);
      expect(second.workspace.profiles, hasLength(1));

      final adminQr = SyncV2PairingCode.encodeQr(
        codes.adminCode,
        administrator: true,
      );
      await second.workspace.recoverAdminBiometric(
        SyncV2PairingCode.decodeQr(adminQr, administrator: true),
      );
      expect(second.workspace.adminUnlocked, isTrue);
      final importedProfile = second.workspace.profiles.singleWhere(
        (profile) => !profile.isNormal,
      );
      await second.workspace.selectProfile(importedProfile.id);
      expect(
        second.workspace.notes.single.note.title,
        'QR paired private note',
      );
      expect(
        second.workspace.notes.single.note.body,
        'available only after administrator recovery',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  for (final biometricSetup in [false, true]) {
    test(
      'cancel unpublished setup removes local credentials (biometrics=$biometricSetup)',
      () async {
        final cloud = _Cloud();
        final biometric = _Biometrics();
        final device = _Device(cloud, biometrics: biometric);
        final c = device.workspace;
        addTearDown(c.dispose);
        await c.initialize();
        final codes = biometricSetup
            ? await c.prepareNewBiometric()
            : await c.prepareNew('1234');
        final generation = SyncV2DeviceTransfer(
          syncCode: codes.syncCode,
          adminCode: codes.adminCode,
        ).generationId;
        final before = await c.deviceAdminStore.read(
          accountId: 'account',
          generationId: generation,
        );
        expect(before, isNotNull);
        before?.destroy();
        await c.cancelSetup();
        expect(c.hasPreparedSetup, isFalse);
        expect(c.registered, isFalse);
        expect(cloud.registryWrites, 0);
        expect(await device.store.read('sync.v2.admin.$generation'), isNull);
        expect(
          await device.store.read('sync.v2.biometric.$generation'),
          isNull,
        );
        expect(biometric.keys.containsKey(generation), isFalse);
        final remembered = await c.deviceAdminStore.read(
          accountId: 'account',
          generationId: generation,
        );
        expect(remembered, isNull);
        await c.prepareNew('5678');
        await c.confirmSetup();
        expect(c.registered, isTrue);
      },
    );
  }

  test('cancel preserves credentials for pending cloud registration', () async {
    final cloud = _Cloud();
    final device = _Device(cloud);
    final c = device.workspace;
    addTearDown(c.dispose);
    await c.initialize();
    final codes = await c.prepareNew('1234');
    final generation = SyncV2DeviceTransfer(
      syncCode: codes.syncCode,
      adminCode: codes.adminCode,
    ).generationId;
    cloud.rejectPreparation = true;
    await expectLater(
      c.confirmSetup(),
      throwsA(isA<SyncV2WorkspaceException>()),
    );
    expect(c.hasPending, isTrue);
    await c.cancelSetup();
    expect(c.hasPreparedSetup, isFalse);
    expect(await device.store.read('sync.v2.admin.$generation'), isNotNull);
    cloud.rejectPreparation = false;
    await c.resumePending();
    await c.unlockAdmin('1234');
    expect(c.adminUnlocked, isTrue);
  });

  test('failed cleanup still discards in-memory prepared setup', () async {
    final device = _Device(_Cloud());
    final c = device.workspace;
    addTearDown(c.dispose);
    await c.initialize();
    await c.prepareNew('1234');
    device.store.failDeletes = true;
    await expectLater(
      c.cancelSetup(),
      throwsA(isA<SyncV2WorkspaceException>()),
    );
    expect(c.hasPreparedSetup, isFalse);
    expect(c.registered, isFalse);
  });

  test('biometric setup needs no password and late unlock cannot survive background', () async {
    final cloud = _Cloud();
    final biometric = _Biometrics();
    final device = _Device(cloud, biometrics: biometric);
    addTearDown(device.workspace.dispose);
    final c = device.workspace;
    await c.initialize();
    expect(c.biometricsAvailable, isTrue);
    final codes = await c.prepareNewBiometric();
    expect(c.preparedUsesBiometrics, isTrue);
    expect(cloud.registryWrites, 0);
    c.background();
    await c.resume();
    expect(await c.prepareNewBiometric(), codes);
    await c.confirmSetup();
    expect(c.registered, isTrue);
    expect(c.biometricEnabled, isTrue);
    expect(c.adminUnlocked, isTrue);
    expect(await device.store.read('sync.v2.admin.${c.generationId}'), isNull);
    c.lockPrivate();
    await c.deviceAdminStore.delete(
      accountId: c.accountId!,
      generationId: c.generationId!,
    );
    biometric.cancel = true;
    await expectLater(
      c.unlockAdminBiometric(),
      throwsA(isA<SyncV2WorkspaceException>()),
    );
    expect(c.error, 'authentication_cancelled');
    expect(c.adminUnlocked, isFalse);
    biometric.cancel = false;
    await c.unlockAdminBiometric();
    expect(c.adminUnlocked, isTrue);
    final migratedGrant = await c.deviceAdminStore.read(
      accountId: c.accountId!,
      generationId: c.generationId!,
    );
    expect(migratedGrant, isNotNull);
    migratedGrant!.destroy();
    c.lockPrivate();
    biometric.entered = Completer<void>();
    biometric.release = Completer<void>();
    final lateUnlock = expectLater(
      c.unlockAdminBiometric(),
      throwsA(isA<SyncV2WorkspaceException>()),
    );
    await biometric.entered!.future;
    c.background();
    biometric.release!.complete();
    await lateUnlock;
    expect(c.adminUnlocked, isFalse);
    expect(c.notes, isEmpty);
    await c.resume();
    final second = _Device(cloud);
    addTearDown(second.workspace.dispose);
    await second.workspace.initialize();
    await second.workspace.recover(codes.syncCode);
    expect(second.workspace.adminUnlocked, isFalse);
    await second.workspace.recoverAdminBiometric(codes.adminCode);
    expect(second.workspace.adminUnlocked, isTrue);
    expect(second.workspace.biometricEnabled, isTrue);
  });

  test(
    'settings admin session creates profiles and setup stores a device grant',
    () async {
      final cloud = _Cloud();
      var settingsAuthenticated = false;
      final device = _Device(
        cloud,
        settingsAdminAuthenticated: () => settingsAuthenticated,
      );
      addTearDown(device.workspace.dispose);
      final c = device.workspace;
      await c.initialize();
      await c.prepareNewBiometric();
      await c.confirmSetup();
      final stored = await c.deviceAdminStore.read(
        accountId: c.accountId!,
        generationId: c.generationId!,
      );
      expect(stored, isNotNull);
      stored!.destroy();

      c.lockPrivate();
      await expectLater(
        c.unlockAdminFromSettings(),
        throwsA(isA<SyncV2WorkspaceException>()),
      );
      expect(c.error, 'admin_required');
      settingsAuthenticated = true;
      expect(await c.unlockAdminFromSettings(), isTrue);
      expect(c.adminUnlocked, isTrue);
      expect((await c.showRecoveryCodes()).adminCode, isNull);
      await expectLater(
        c.configureAdminPassword('4321'),
        throwsA(isA<SyncV2WorkspaceException>()),
      );
      expect(c.error, 'admin_required');
      await expectLater(
        c.deviceTransfer(),
        throwsA(isA<SyncV2WorkspaceException>()),
      );
      await expectLater(
        c.enableAdminBiometrics(),
        throwsA(isA<SyncV2WorkspaceException>()),
      );
      expect(c.error, 'admin_required');

      await c.createProfile('Settings profile', '8765');
      await c.saveNote(title: 'Created through settings', body: 'private body');
      expect(c.profiles, hasLength(2));
      await c.selectProfile(c.profiles.singleWhere((p) => !p.isNormal).id);
      expect(c.notes.single.note.title, 'Created through settings');
      // Admin credentials stay device-owned, but an administrator session from
      // settings may still change profile passcodes: the administrator takes
      // precedence over every profile.
      expect(c.canManageAdminCredentials, isFalse);
      final restoredId = c.selectedProfileId!;
      await c.changeProfilePassword(restoredId, '5678');
      c.lockSettingsAdmin();
      await c.unlockPrivate('5678');
      expect(c.profiles.any((p) => p.id == restoredId), isTrue);
      c.lockPrivate();
      expect(c.adminUnlocked, isFalse);
      expect(c.notes, isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'settings lock during device-key read or verification cancels admin unlock',
    () async {
      final cloud = _Cloud();
      var settingsAuthenticated = true;
      final device = _Device(
        cloud,
        settingsAdminAuthenticated: () => settingsAuthenticated,
      );
      addTearDown(device.workspace.dispose);
      final c = device.workspace;
      await c.initialize();
      await c.prepareNewBiometric();
      await c.confirmSetup();

      device.store.deviceAdminReadEntered = Completer<void>();
      device.store.deviceAdminReadRelease = Completer<void>();
      final duringRead = expectLater(
        c.unlockAdminFromSettings(),
        throwsA(isA<SyncV2WorkspaceException>()),
      );
      await device.store.deviceAdminReadEntered!.future;
      c.lockPrivate();
      device.store.deviceAdminReadRelease!.complete();
      await duringRead;
      expect(c.adminUnlocked, isFalse);

      device.store.enrollmentReadEntered = Completer<void>();
      device.store.enrollmentReadRelease = Completer<void>();
      final duringVerification = expectLater(
        c.unlockAdminFromSettings(),
        throwsA(isA<SyncV2WorkspaceException>()),
      );
      await device.store.enrollmentReadEntered!.future;
      c.lockPrivate();
      device.store.enrollmentReadRelease!.complete();
      await duringVerification;
      expect(c.adminUnlocked, isFalse);

      device.store.deviceAdminReadEntered = Completer<void>();
      device.store.deviceAdminReadRelease = Completer<void>();
      final acrossSettingsRelock = expectLater(
        c.unlockAdminFromSettings(),
        throwsA(isA<SyncV2WorkspaceException>()),
      );
      await device.store.deviceAdminReadEntered!.future;
      settingsAuthenticated = false;
      c.lockSettingsAdmin();
      settingsAuthenticated = true;
      device.store.deviceAdminReadRelease!.complete();
      await acrossSettingsRelock;
      expect(c.adminUnlocked, isFalse);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('SYNC-only recovery has no device admin grant', () async {
    final cloud = _Cloud();
    final first = _Device(cloud);
    addTearDown(first.workspace.dispose);
    await first.workspace.initialize();
    final codes = await first.workspace.prepareNewBiometric();
    await first.workspace.confirmSetup();

    var settingsAuthenticated = true;
    final second = _Device(
      cloud,
      settingsAdminAuthenticated: () => settingsAuthenticated,
    );
    addTearDown(second.workspace.dispose);
    await second.workspace.initialize();
    await second.workspace.recover(codes.syncCode);
    expect(
      await second.workspace.deviceAdminStore.read(
        accountId: second.workspace.accountId!,
        generationId: second.workspace.generationId!,
      ),
      isNull,
    );
    expect(await second.workspace.unlockAdminFromSettings(), isFalse);
    expect(second.workspace.adminUnlocked, isFalse);
    settingsAuthenticated = false;
    await expectLater(
      second.workspace.unlockAdminFromSettings(),
      throwsA(isA<SyncV2WorkspaceException>()),
    );
    expect(second.workspace.error, 'admin_required');
  }, timeout: const Timeout(Duration(minutes: 2)));

  for (final failure in [
    const FormatException('unsupported catalog'),
    const HimemoDecryptionException(),
  ]) {
    test(
      'catalog failure preserves a verified settings ADMIN key ($failure)',
      () async {
        late _ProjectedNotesRepository repository;
        final device = _Device(
          _Cloud(),
          settingsAdminAuthenticated: () => true,
          repositoryFactory: (inbox, headers, payloads) =>
              repository = _ProjectedNotesRepository(inbox, headers, payloads),
        );
        final c = device.workspace;
        addTearDown(c.dispose);
        await c.initialize();
        await c.prepareNew('1234');
        await c.confirmSetup();
        c.lockPrivate();
        repository.catalogFailure = failure;
        expect(await c.unlockAdminFromSettings(), isFalse);
        expect(c.adminUnlocked, isFalse);
        final remembered = await c.deviceAdminStore.read(
          accountId: c.accountId!,
          generationId: c.generationId!,
        );
        expect(remembered, isNotNull);
        remembered?.destroy();
        repository.catalogFailure = null;
        expect(await c.unlockAdminFromSettings(), isTrue);
      },
    );
  }

  for (final corruptEnvelope in [true, false]) {
    test(
      'registration proof failure keeps a valid device ADMIN key (envelope=$corruptEnvelope)',
      () async {
        final device = _Device(
          _Cloud(),
          settingsAdminAuthenticated: () => true,
        );
        final c = device.workspace;
        addTearDown(c.dispose);
        await c.initialize();
        await c.prepareNew('1234');
        await c.confirmSetup();
        c.lockPrivate();
        const proofKey = 'security.icloud_sync_v2.verified_proof.v1';
        final proof = (await device.store.read(proofKey))!;
        await device.store.write(
          proofKey,
          corruptEnvelope
              ? '{invalid'
              : jsonEncode({
                  ...jsonDecode(proof) as Map,
                  'proof': 'invalid ciphertext',
                }),
        );
        expect(await c.unlockAdminFromSettings(), isFalse);
        final key = await c.deviceAdminStore.read(
          accountId: c.accountId!,
          generationId: c.generationId!,
        );
        expect(key, isNotNull);
        key?.destroy();
        await device.store.write(proofKey, proof);
        expect(await c.unlockAdminFromSettings(), isTrue);
      },
    );
  }

  test('settings ADMIN verification rejects a different enrolled generation without deleting its key', () async {
    final device = _Device(_Cloud(), settingsAdminAuthenticated: () => true);
    final c = device.workspace;
    addTearDown(c.dispose);
    await c.initialize();
    await c.prepareNew('1234');
    await c.confirmSetup();
    c.lockPrivate();
    final originalGeneration = c.generationId!;
    const enrollmentKey = 'security.icloud_sync_v2.enrollment.v1';
    final original = (await device.store.read(enrollmentKey))!;
    await device.store.write(
      enrollmentKey,
      jsonEncode({
        ...jsonDecode(original) as Map,
        'generation': 'other_generation',
      }),
    );
    expect(await c.unlockAdminFromSettings(), isFalse);
    final retained = await c.deviceAdminStore.read(
      accountId: c.accountId!,
      generationId: originalGeneration,
    );
    expect(retained, isNotNull);
    retained?.destroy();
    await device.store.write(enrollmentKey, original);
    expect(await c.unlockAdminFromSettings(), isTrue);
  });

  test(
    'invalid device grant is deleted and falls back to original credentials',
    () async {
      final cloud = _Cloud();
      var settingsAuthenticated = true;
      final device = _Device(
        cloud,
        settingsAdminAuthenticated: () => settingsAuthenticated,
      );
      addTearDown(device.workspace.dispose);
      final c = device.workspace;
      await c.initialize();
      await c.prepareNewBiometric();
      await c.confirmSetup();
      c.lockPrivate();
      final key = c.deviceAdminStore.storageKey(
        installationId: 'test-installation',
        accountId: c.accountId!,
        generationId: c.generationId!,
      );
      await device.store.write(key, '{invalid-json');

      expect(await c.unlockAdminFromSettings(), isFalse);
      expect(c.adminUnlocked, isFalse);
      expect(await device.store.read(key), isNull);
      // The original biometric credential remains available after bad-cache
      // cleanup and can repopulate a valid cache entry.
      await c.unlockAdminBiometric();
      expect(c.adminUnlocked, isTrue);
      final repaired = await c.deviceAdminStore.read(
        accountId: c.accountId!,
        generationId: c.generationId!,
      );
      expect(repaired, isNotNull);
      repaired!.destroy();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'device grant write failures do not block setup or biometric unlock',
    () async {
      final cloud = _Cloud();
      final device = _Device(cloud);
      addTearDown(device.workspace.dispose);
      final c = device.workspace;
      await c.initialize();
      device.store.failDeviceAdminWrites = true;
      await c.prepareNewBiometric();
      await c.confirmSetup();
      expect(c.registered, isTrue);
      expect(c.adminUnlocked, isTrue);
      expect(
        await c.deviceAdminStore.read(
          accountId: c.accountId!,
          generationId: c.generationId!,
        ),
        isNull,
      );

      c.lockPrivate();
      await c.unlockAdminBiometric();
      expect(c.adminUnlocked, isTrue);
      expect(
        await c.deviceAdminStore.read(
          accountId: c.accountId!,
          generationId: c.generationId!,
        ),
        isNull,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('sync status distinguishes syncing, successful completion, and connection errors', () async {
    final cloud = _Cloud();
    final device = _Device(cloud);
    addTearDown(device.workspace.dispose);
    final c = device.workspace;
    await c.initialize();
    await c.prepareNew('1234');
    await c.confirmSetup();
    expect(c.lastSyncCompletedAt, isNull);
    device.syncEntered = Completer<void>();
    device.syncRelease = Completer<void>();
    final sync = c.syncNow();
    await device.syncEntered!.future;
    expect(c.syncing, isTrue);
    device.syncRelease!.complete();
    await sync;
    expect(c.syncing, isFalse);
    expect(c.lastSyncCompletedAt, isNotNull);
    expect(c.syncError, isNull);
    final completed = c.lastSyncCompletedAt;
    cloud.offline = true;
    await expectLater(c.syncNow(), throwsA(isA<SyncV2WorkspaceException>()));
    expect(c.syncing, isFalse);
    expect(c.syncError, isNotNull);
    expect(c.lastSyncCompletedAt, completed);
    cloud.offline = false;
    await c.syncNow();
    expect(c.syncError, isNull);
  });

  test(
    'device transfer grants both roles with a device-local passcode',
    () async {
      final cloud = _Cloud();
      final first = _Device(cloud);
      final second = _Device(cloud);
      addTearDown(first.workspace.dispose);
      addTearDown(second.workspace.dispose);
      final a = first.workspace;
      final b = second.workspace;
      await a.initialize();
      await a.prepareNew('1234');
      await a.confirmSetup();
      await a.createProfile('private', '5678');
      await a.saveNote(title: 'private note', body: 'body');
      await a.syncNow();
      final transfer = await a.deviceTransfer();
      await b.initialize();
      await b.recoverDeviceTransfer(transfer, adminPassword: '4321');
      expect(b.canManageAdminCredentials, isTrue);
      await b.selectProfile(b.profiles.singleWhere((p) => !p.isNormal).id);
      expect(b.notes.single.note.title, 'private note');
      b.lockPrivate();
      await expectLater(
        b.unlockAdmin('1234'),
        throwsA(isA<SyncV2WorkspaceException>()),
      );
      await b.unlockAdmin('4321');
      expect(b.adminUnlocked, isTrue);
      a.lockPrivate();
      await a.unlockAdmin('1234');
      expect(a.adminUnlocked, isTrue);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('invalid combined ADMIN never persists enrollment or a device grant', () async {
    final cloud = _Cloud();
    final first = _Device(cloud);
    final second = _Device(cloud);
    addTearDown(first.workspace.dispose);
    addTearDown(second.workspace.dispose);
    await first.workspace.initialize();
    await first.workspace.prepareNew('1234');
    await first.workspace.confirmSetup();
    final valid = await first.workspace.deviceTransfer();
    final wrong =
        'himemo-admin-v2:${base64Url.encode(utf8.encode(jsonEncode({'generation': valid.generationId, 'key': base64Encode(List.filled(32, 99))})))}';
    await second.workspace.initialize();
    await expectLater(
      second.workspace.recoverDeviceTransfer(
        SyncV2DeviceTransfer(syncCode: valid.syncCode, adminCode: wrong),
        adminPassword: '4321',
      ),
      throwsA(isA<SyncV2WorkspaceException>()),
    );
    expect(second.workspace.registered, isFalse);
    expect(await second.enrollment.readForAccount('account'), isNull);
    expect(
      await second.workspace.deviceAdminStore.read(
        accountId: 'account',
        generationId: valid.generationId,
      ),
      isNull,
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('SYNC-only transfer grants no ADMIN and switching local methods removes the old credential', () async {
    final cloud = _Cloud();
    final biometric = _Biometrics();
    final first = _Device(cloud, biometrics: biometric);
    final second = _Device(cloud);
    addTearDown(first.workspace.dispose);
    addTearDown(second.workspace.dispose);
    final a = first.workspace;
    await a.initialize();
    await a.prepareNew('1234');
    await a.confirmSetup();
    await a.createProfile('private', '5678');
    await a.syncNow();
    final syncOnly = await a.deviceTransfer(includeAdministrator: false);
    await second.workspace.initialize();
    await second.workspace.recoverDeviceTransfer(syncOnly);
    expect(second.workspace.adminUnlocked, isFalse);
    expect(
      await second.workspace.deviceAdminStore.read(
        accountId: 'account',
        generationId: syncOnly.generationId,
      ),
      isNull,
    );
    await expectLater(
      second.workspace.deviceTransfer(),
      throwsA(isA<SyncV2WorkspaceException>()),
    );
    await a.enableAdminBiometrics();
    expect(await first.store.read('sync.v2.admin.${a.generationId}'), isNull);
    expect(a.biometricEnabled, isTrue);
    await expectLater(
      a.configureAdminPassword('5678'),
      throwsA(isA<SyncV2WorkspaceException>()),
    );
    expect(a.error, 'duplicate_passcode');
    expect(a.biometricEnabled, isTrue);
    await a.configureAdminPassword('4321');
    expect(a.biometricEnabled, isFalse);
    expect(biometric.keys, isEmpty);
    a.lockPrivate();
    await expectLater(
      a.unlockAdminBiometric(),
      throwsA(isA<SyncV2WorkspaceException>()),
    );
    await a.unlockAdmin('4321');
    expect(a.adminUnlocked, isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('combined transfer can select biometrics and a cancelled switch preserves the passcode', () async {
    final cloud = _Cloud();
    final biometric = _Biometrics();
    final first = _Device(cloud, biometrics: biometric);
    final receiverBiometric = _Biometrics();
    final second = _Device(cloud, biometrics: receiverBiometric);
    addTearDown(first.workspace.dispose);
    addTearDown(second.workspace.dispose);
    final a = first.workspace;
    await a.initialize();
    await a.prepareNew('1234');
    await a.confirmSetup();
    biometric.cancel = true;
    await expectLater(
      a.enableAdminBiometrics(),
      throwsA(isA<SyncV2WorkspaceException>()),
    );
    expect(a.biometricEnabled, isFalse);
    expect(a.adminPasswordConfigured, isTrue);
    a.lockPrivate();
    await a.unlockAdmin('1234');
    final transfer = await a.deviceTransfer();
    await second.workspace.initialize();
    await second.workspace.recoverDeviceTransfer(transfer, useBiometrics: true);
    expect(second.workspace.biometricEnabled, isTrue);
    expect(second.workspace.adminPasswordConfigured, isFalse);
    second.workspace.lockPrivate();
    await second.workspace.unlockAdminBiometric();
    expect(second.workspace.canManageAdminCredentials, isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test(
    'four character admin password is accepted and biometrics can be enabled',
    () async {
      final device = _Device(_Cloud());
      addTearDown(device.workspace.dispose);
      final c = device.workspace;
      await c.initialize();
      await expectLater(
        c.prepareNew('123'),
        throwsA(isA<SyncV2WorkspaceException>()),
      );
      await c.prepareNew('1234');
      await c.confirmSetup();
      await c.enableAdminBiometrics();
      c.lockPrivate();
      await c.unlockAdminBiometric();
      expect(c.adminUnlocked, isTrue);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'admin and profile passcodes must differ but profiles may share a passcode',
    () async {
      final device = _Device(_Cloud());
      addTearDown(device.workspace.dispose);
      final c = device.workspace;
      await c.initialize();
      final codes = await c.prepareNew('1234');
      await c.confirmSetup();
      await expectLater(
        c.createProfile('duplicate', '1234'),
        throwsA(isA<SyncV2WorkspaceException>()),
      );
      expect(c.error, 'duplicate_passcode');
      await c.createProfile('first', '5678');
      final id = c.selectedProfileId!;
      await c.createProfile('second', '5678');
      await expectLater(
        c.changeProfilePassword(id, '1234'),
        throwsA(isA<SyncV2WorkspaceException>()),
      );
      expect(c.error, 'duplicate_passcode');
      await expectLater(
        c.recoverAdmin(codes.adminCode, '5678'),
        throwsA(isA<SyncV2WorkspaceException>()),
      );
      expect(c.error, 'duplicate_passcode');
      c.lockPrivate();
      await c.unlockPrivate('5678');
      expect(c.profiles.where((p) => !p.isNormal), hasLength(2));
      c.lockPrivate();
      await c.unlockAdmin('1234');
      expect(c.adminUnlocked, isTrue);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'profile rename and deletion persist and synchronize to another admin',
    () async {
      final cloud = _Cloud();
      final first = _Device(cloud);
      final second = _Device(cloud);
      addTearDown(first.workspace.dispose);
      addTearDown(second.workspace.dispose);
      final c = first.workspace;
      await c.initialize();
      final codes = await c.prepareNew('1234');
      await c.confirmSetup();
      await c.createProfile('original', '5678');
      final id = c.selectedProfileId!;
      await c.saveNote(title: 'private note', body: 'delete with profile');
      await c.syncNow();
      await second.workspace.initialize();
      await second.workspace.recover(codes.syncCode);
      await second.workspace.recoverAdmin(codes.adminCode, '4321');
      second.workspace.lockPrivate();
      await second.workspace.unlockPrivate('5678');
      await c.renameProfile(id, 'renamed');
      await c.syncNow();
      await second.workspace.syncNow();
      expect(
        second.workspace.profiles.singleWhere((p) => p.id == id).name,
        'renamed',
      );
      await c.deleteProfile(id);
      expect(c.notes, isEmpty);
      expect(c.profiles.where((p) => p.id == id), isEmpty);
      await c.syncNow();
      await second.workspace.syncNow();
      expect(second.workspace.profiles.where((p) => p.id == id), isEmpty);
      c.lockPrivate();
      await expectLater(
        c.unlockPrivate('5678'),
        throwsA(isA<SyncV2WorkspaceException>()),
      );
      expect(c.error, 'wrong_password');
      await expectLater(
        c.renameProfile(id, 'denied'),
        throwsA(isA<SyncV2WorkspaceException>()),
      );
      expect(c.error, 'admin_required');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('resume completes an existing registration interrupted during initial restore', () async {
    final cloud = _Cloud();
    final original = _Device(cloud);
    addTearDown(original.workspace.dispose);
    await original.workspace.initialize();
    await original.workspace.prepareNew('administrator password');
    await original.workspace.confirmSetup();
    final reopened = _Device(cloud, sharedStore: original.store);
    addTearDown(reopened.workspace.dispose);
    reopened.store.restoreEntered = Completer<void>();
    reopened.store.restoreRelease = Completer<void>();
    final initial = expectLater(
      reopened.workspace.initialize(),
      throwsA(isA<SyncV2WorkspaceException>()),
    );
    await reopened.store.restoreEntered!.future;
    reopened.workspace.background();
    reopened.store.restoreRelease!.complete();
    await initial;
    expect(reopened.workspace.registered, isFalse);
    expect(reopened.workspace.notes, isEmpty);
    await reopened.workspace.resume();
    expect(reopened.workspace.registered, isTrue);
    expect(reopened.workspace.profiles.length, 1);
    await expectLater(
      reopened.workspace.prepareNew('another admin password'),
      throwsA(isA<SyncV2WorkspaceException>()),
    );
  });
  test('setup keeps the same codes across background and rejects switched accounts', () async {
    final cloud = _Cloud();
    final device = _Device(cloud);
    addTearDown(device.workspace.dispose);
    await device.workspace.initialize();
    final codes = await device.workspace.prepareNew('administrator password');
    expect(cloud.registryWrites, 0);
    device.workspace.background();
    await device.workspace.resume();
    final continued = await device.workspace.prepareNew(
      'administrator password',
    );
    expect(continued, codes);
    expect(cloud.registryWrites, 0);
    await device.workspace.confirmSetup();
    await device.workspace.createProfile('Private', 'private password');
    final generation = device.workspace.generationId;
    expect(device.workspace.profiles.length, 2);
    cloud.account = 'different-account';
    await expectLater(
      device.workspace.recover(codes.syncCode),
      throwsA(isA<SyncV2WorkspaceException>()),
    );
    expect(device.workspace.accountId, 'account');
    expect(device.workspace.generationId, generation);
    expect(device.workspace.profiles.length, 1);
    expect(device.workspace.adminUnlocked, isFalse);
    expect(device.workspace.notes, isEmpty);
  });
  test('editing rich blocks syncs updated text without removed attachment references', () async {
    final cloud = _Cloud();
    final a = _Device(cloud), b = _Device(cloud);
    addTearDown(a.workspace.dispose);
    addTearDown(b.workspace.dispose);
    await a.workspace.initialize();
    await b.workspace.initialize();
    final codes = await a.workspace.prepareNew('administrator password');
    await a.workspace.confirmSetup();
    const photo = NoteAttachment(
      type: AttachmentType.photo,
      label: 'old photo',
      filePath: 'v2pending:photo',
    );
    final rich = NoteEntry(
      id: 'legacy-rich',
      vaultId: 'everyday',
      title: 'Rich note',
      body: 'Old paragraph',
      createdAt: DateTime.utc(2020),
      attachments: [photo],
      blocks: [
        const NoteBlock(type: NoteBlockType.paragraph, text: 'Old paragraph'),
        const NoteBlock(type: NoteBlockType.photo, attachment: photo),
      ],
    );
    await a.workspace.saveNote(
      title: rich.title,
      body: rich.body,
      createdAt: rich.createdAt,
      blocks: rich.blocks,
      addedFiles: [
        SyncV2PendingAttachment(
          label: photo.label,
          type: photo.type,
          bytes: Uint8List.fromList([1, 2, 3]),
          draftId: 'photo',
        ),
      ],
    );
    final imported = a.workspace.notes.single;
    expect(imported.note.blocks.map((block) => block.type), [
      NoteBlockType.paragraph,
      NoteBlockType.photo,
    ]);
    expect(imported.attachments, hasLength(1));
    await expectLater(
      a.workspace.saveNote(
        original: _UnavailableWorkspaceNote(imported),
        title: imported.note.title,
        body: syncV2EditableBody(imported.note),
        isPinned: true,
      ),
      throwsA(
        isA<SyncV2WorkspaceException>().having(
          (error) => error.code,
          'code',
          'conflict',
        ),
      ),
    );
    await a.workspace.saveNote(
      original: imported,
      title: 'Renamed rich note',
      body: syncV2EditableBody(imported.note),
      isPinned: true,
    );
    final renamed = a.workspace.notes.single;
    expect(renamed.note.isPinned, isTrue);
    expect(renamed.note.blocks, imported.note.blocks);
    expect(
      renamed.attachments.map((ref) => ref.toJson()).toList(),
      imported.attachments.map((ref) => ref.toJson()).toList(),
    );
    await expectLater(
      a.workspace.saveNote(
        original: renamed,
        title: 'Unsafe flattened edit',
        body: 'Updated paragraph',
      ),
      throwsA(
        isA<SyncV2WorkspaceException>().having(
          (error) => error.code,
          'code',
          'rich_blocks_required',
        ),
      ),
    );
    await expectLater(
      a.workspace.saveNote(
        original: renamed,
        title: 'Dropped attachment',
        body: syncV2EditableBody(renamed.note),
        blocks: [renamed.note.blocks[0]],
      ),
      throwsA(
        isA<SyncV2WorkspaceException>().having(
          (error) => error.code,
          'code',
          'rich_blocks_structure_changed',
        ),
      ),
    );
    await expectLater(
      a.workspace.saveNote(
        original: renamed,
        title: renamed.note.title,
        body: syncV2EditableBody(renamed.note),
        blocks: [
          renamed.note.blocks[1],
          renamed.note.blocks[1],
          renamed.note.blocks[0],
        ],
      ),
      throwsA(
        isA<SyncV2WorkspaceException>().having(
          (error) => error.code,
          'code',
          'rich_blocks_structure_changed',
        ),
      ),
    );
    await expectLater(
      a.workspace.saveNote(
        original: renamed,
        title: renamed.note.title,
        body: syncV2EditableBody(renamed.note),
        blocks: [
          renamed.note.blocks[0],
          renamed.note.blocks[1].copyWith(
            attachment: renamed.note.blocks[1].attachment!.copyWith(
              label: 'Forged attachment',
            ),
          ),
        ],
      ),
      throwsA(
        isA<SyncV2WorkspaceException>().having(
          (error) => error.code,
          'code',
          'rich_blocks_structure_changed',
        ),
      ),
    );
    await a.workspace.saveNote(
      original: renamed,
      title: renamed.note.title,
      body: syncV2EditableBody(renamed.note),
      blocks: [renamed.note.blocks[1], renamed.note.blocks[0]],
    );
    final reordered = a.workspace.notes.single;
    expect(reordered.note.blocks.first.type, NoteBlockType.photo);
    expect(
      reordered.note.blocks.first.attachment,
      renamed.note.blocks[1].attachment,
    );
    await a.workspace.saveNote(
      original: reordered,
      title: 'Edited rich note',
      body: 'Updated paragraph\n\nSecond paragraph',
      blocks: [
        const NoteBlock(
          type: NoteBlockType.paragraph,
          text: 'Updated paragraph',
        ),
        const NoteBlock(
          type: NoteBlockType.paragraph,
          text: 'Second paragraph',
        ),
        reordered.note.blocks[0],
      ],
      removedAttachmentIds: [imported.attachments.single.id],
    );
    final updated = a.workspace.notes.single;
    expect(updated.note.body, 'Updated paragraph\n\nSecond paragraph');
    expect(updated.note.isPinned, isTrue);
    expect(updated.note.blocks.map((block) => block.text), [
      'Updated paragraph',
      'Second paragraph',
    ]);
    expect(
      updated.note.blocks.any((block) => block.attachment != null),
      isFalse,
    );
    expect(updated.note.attachments, isEmpty);
    expect(updated.attachments, isEmpty);
    await a.workspace.syncNow();
    await b.workspace.recover(codes.syncCode);
    expect(b.workspace.registered, isTrue);
    final roundTripped = b.workspace.notes.single;
    expect(roundTripped.note.body, 'Updated paragraph\n\nSecond paragraph');
    expect(roundTripped.note.blocks, updated.note.blocks);
    expect(roundTripped.note.isPinned, isTrue);
    expect(roundTripped.attachments, isEmpty);
    expect(roundTripped.note.attachments, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));
  test(
    'quick mode keeps body text out of blocks across repeated edits',
    () async {
      final cloud = _Cloud();
      final device = _Device(cloud);
      addTearDown(device.workspace.dispose);
      await device.workspace.initialize();
      await device.workspace.prepareNew('administrator password');
      await device.workspace.confirmSetup();
      final quick = NoteEntry(
        id: 'note_quick-body-only',
        vaultId: 'everyday',
        title: 'Quick note',
        body: 'Original body',
        createdAt: DateTime.utc(2020),
        editorMode: NoteEditorMode.quick,
      );
      await _seedNativeNote(device, quick);
      var note = device.workspace.notes.single;
      expect(note.note.editorMode, NoteEditorMode.quick);
      expect(note.note.blocks, isEmpty);
      await device.workspace.saveNote(
        original: note,
        title: note.note.title,
        body: 'Updated body',
      );
      note = device.workspace.notes.single;
      expect(note.note.body, 'Updated body');
      expect(note.note.blocks, isEmpty);
      await device.workspace.saveNote(
        original: note,
        title: 'Edited again',
        body: note.note.body,
      );
      expect(device.workspace.notes.single.note.blocks, isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test(
    'pending rich attachments resolve to encrypted refs and survive sync',
    () async {
      final cloud = _Cloud();
      final a = _Device(cloud);
      final b = _Device(cloud);
      addTearDown(a.workspace.dispose);
      addTearDown(b.workspace.dispose);
      await a.workspace.initialize();
      final codes = await a.workspace.prepareNewBiometric();
      await a.workspace.confirmSetup();
      const pendingId = 'pending-draft-01';
      const textBlock = NoteBlock(
        type: NoteBlockType.paragraph,
        text: 'Draft text',
      );
      final placeholder = NoteBlock(
        type: NoteBlockType.file,
        attachment: const NoteAttachment(
          type: AttachmentType.file,
          label: 'private.txt',
          filePath: 'v2pending:$pendingId',
        ),
      );
      await a.workspace.saveNote(
        title: 'Pending insertion',
        body: 'Draft text',
        blocks: [textBlock, placeholder],
        addedFiles: [
          SyncV2PendingAttachment(
            label: 'private.txt',
            type: AttachmentType.file,
            bytes: Uint8List.fromList([4, 5, 6]),
            draftId: pendingId,
          ),
        ],
      );
      final saved = a.workspace.notes.single;
      expect(saved.note.blocks.first, textBlock);
      expect(
        saved.note.blocks.last.attachment!.filePath,
        startsWith('v2attachment:'),
      );
      expect(
        saved.note.blocks.last.attachment!.syncAttachmentContentHash,
        isNotNull,
      );
      expect(
        saved.note.blocks.any(
          (block) =>
              block.attachment?.filePath?.startsWith('v2pending:') ?? false,
        ),
        isFalse,
      );

      for (final invalid in [
        (
          blocks: [textBlock, placeholder],
          files: const <SyncV2PendingAttachment>[],
        ),
        (
          blocks: [textBlock],
          files: [
            SyncV2PendingAttachment(
              label: 'private.txt',
              type: AttachmentType.file,
              bytes: Uint8List.fromList([1]),
              draftId: 'missing-placeholder',
            ),
          ],
        ),
        (
          blocks: [textBlock, placeholder, placeholder],
          files: [
            SyncV2PendingAttachment(
              label: 'private.txt',
              type: AttachmentType.file,
              bytes: Uint8List.fromList([1]),
              draftId: pendingId,
            ),
          ],
        ),
        (
          blocks: [
            textBlock,
            const NoteBlock(
              type: NoteBlockType.file,
              attachment: NoteAttachment(
                type: AttachmentType.file,
                label: 'private.txt',
                filePath: 'v2pending:unknown',
              ),
            ),
          ],
          files: const <SyncV2PendingAttachment>[],
        ),
      ]) {
        await expectLater(
          a.workspace.saveNote(
            title: 'Invalid pending',
            body: 'Draft text',
            blocks: invalid.blocks,
            addedFiles: invalid.files,
          ),
          throwsA(
            isA<SyncV2WorkspaceException>().having(
              (error) => error.code,
              'code',
              'rich_attachment_pending_invalid',
            ),
          ),
        );
      }

      await a.workspace.syncNow();
      await b.workspace.recover(codes.syncCode);
      expect(b.workspace.registered, isTrue);
      final imported = b.workspace.notes.single;
      expect(imported.note.blocks.first, saved.note.blocks.first);
      expect(imported.note.blocks.last.type, NoteBlockType.file);
      expect(imported.note.blocks.last.attachment!.label, 'private.txt');
      expect(
        imported.note.blocks.last.attachment!.filePath,
        startsWith('v2attachment:'),
      );
      expect(
        imported.note.blocks.last.attachment!.syncAttachmentContentHash,
        saved.note.blocks.last.attachment!.syncAttachmentContentHash,
      );
      expect(imported.attachments, hasLength(1));
      expect(await b.workspace.readAttachment(imported.attachments.single), [
        4,
        5,
        6,
      ]);
      expect(
        imported.note.blocks.any(
          (block) =>
              block.attachment?.filePath?.startsWith('v2pending:') ?? false,
        ),
        isFalse,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'lock during encrypted attachment storage rolls back note and chunks',
    () async {
      late _HeldBatchRepository heldRepository;
      final cloud = _Cloud();
      final device = _Device(
        cloud,
        repositoryFactory: (inbox, headers, payloads) =>
            heldRepository = _HeldBatchRepository(inbox, headers, payloads),
      );
      addTearDown(device.workspace.dispose);
      await device.workspace.initialize();
      await device.workspace.prepareNewBiometric();
      await device.workspace.confirmSetup();
      final originalBlock = const NoteBlock(
        type: NoteBlockType.paragraph,
        text: 'Protected text',
      );
      await device.workspace.saveNote(
        title: 'Protected note',
        body: 'Protected text',
        blocks: [originalBlock],
      );
      final original = device.workspace.notes.single;
      heldRepository
        ..entered = Completer<void>()
        ..release = Completer<void>();
      final draftId = 'pending-during-lock';
      final saving = device.workspace.saveNote(
        original: original,
        title: 'Must roll back',
        body: 'Protected text',
        blocks: [
          originalBlock,
          const NoteBlock(
            type: NoteBlockType.file,
            attachment: NoteAttachment(
              type: AttachmentType.file,
              label: 'secret.bin',
              filePath: 'v2pending:pending-during-lock',
            ),
          ),
        ],
        addedFiles: [
          SyncV2PendingAttachment(
            label: 'secret.bin',
            type: AttachmentType.file,
            bytes: Uint8List.fromList([7, 8, 9]),
            draftId: draftId,
          ),
        ],
      );
      await heldRepository.entered!.future;
      device.workspace.background();
      heldRepository.release!.complete();
      await expectLater(
        saving,
        throwsA(
          isA<SyncV2WorkspaceException>().having(
            (error) => error.code,
            'code',
            'locked',
          ),
        ),
      );
      await device.workspace.resume();
      expect(device.workspace.notes, hasLength(1));
      expect(device.workspace.notes.single.note.title, 'Protected note');
      expect(device.workspace.notes.single.attachments, isEmpty);
      expect(
        await device.inbox.readPage(
          generationId: device.workspace.generationId!,
          limit: 100,
        ),
        hasLength(1),
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'attachment previews are quiet, cancellable and keep the queue usable',
    () async {
      final cloud = _Cloud();
      final device = _Device(cloud);
      addTearDown(device.workspace.dispose);
      await device.workspace.initialize();
      await device.workspace.prepareNewBiometric();
      await device.workspace.confirmSetup();
      await device.workspace.createProfile('Research', 'private password');
      final privateId = device.workspace.selectedProfileId!;
      final normalId = device.workspace.profiles
          .singleWhere((p) => p.isNormal)
          .id;
      final photo = Uint8List.fromList(List.generate(2048, (i) => i % 251));
      await device.workspace.saveNote(
        title: 'Preview',
        body: 'Attachment preview test',
        addedFiles: [
          SyncV2PendingAttachment(
            label: 'photo',
            type: AttachmentType.photo,
            bytes: photo,
          ),
        ],
      );
      final reference = device.workspace.notes.single.attachments.single;
      var notifications = 0;
      void listener() => notifications++;
      device.workspace.addListener(listener);
      expect(device.workspace.busy, isFalse);
      expect(await device.workspace.readAttachmentPreview(reference), photo);
      expect(device.workspace.busy, isFalse);
      expect(notifications, 0);
      device.workspace.removeListener(listener);

      final badReference = SyncV2AttachmentReference(
        id: reference.id,
        label: reference.label,
        type: reference.type,
        size: reference.size,
        sha256: '0' * 64,
        chunks: reference.chunks,
      );
      await expectLater(
        device.workspace.readAttachmentPreview(badReference),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        device.workspace.readAttachmentPreview(
          reference,
          isActive: () => false,
        ),
        throwsA(isA<SyncV2WorkspaceException>()),
      );
      expect(await device.workspace.readAttachmentPreview(reference), photo);

      // A queued read is rejected if the selected profile changes before it
      // reaches the head of the serialized workspace queue.
      device.syncEntered = Completer<void>();
      device.syncRelease = Completer<void>();
      final heldSync = device.workspace.syncNow();
      await device.syncEntered!.future;
      final staleBySelection = device.workspace.readAttachmentPreview(
        reference,
      );
      device.workspace.selectedProfileId = normalId;
      device.syncRelease!.complete();
      await heldSync;
      await expectLater(
        staleBySelection,
        throwsA(isA<SyncV2WorkspaceException>()),
      );
      await device.workspace.selectProfile(privateId);

      // Backgrounding also invalidates a queued preview; subsequent operations
      // still run after the failed read.
      device.syncEntered = Completer<void>();
      device.syncRelease = Completer<void>();
      final secondHeldSync = device.workspace.syncNow();
      await device.syncEntered!.future;
      final staleByLock = device.workspace.readAttachmentPreview(reference);
      device.workspace.background();
      device.syncRelease!.complete();
      await secondHeldSync;
      await expectLater(staleByLock, throwsA(isA<SyncV2WorkspaceException>()));
      await device.workspace.resume();
      await device.workspace.unlockPrivate('private password');
      expect(await device.workspace.readAttachmentPreview(reference), photo);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'revoking a workspace clears its unlocked session immediately',
    () async {
      final cloud = _Cloud();
      final device = _Device(cloud);
      addTearDown(device.workspace.dispose);
      await device.workspace.initialize();
      await device.workspace.prepareNewBiometric();
      await device.workspace.confirmSetup();
      await device.workspace.saveNote(
        title: 'private session',
        body: 'content',
      );
      device.syncEntered = Completer<void>();
      device.syncRelease = Completer<void>();
      final pendingSync = device.workspace.syncNow();
      await device.syncEntered!.future;
      final revision = device.workspace.privateSessionRevision;
      expect(device.workspace.notes, isNotEmpty);
      device.workspace.revokeSession();
      expect(device.workspace.registered, isFalse);
      expect(device.workspace.accountId, isNull);
      expect(device.workspace.generationId, isNull);
      expect(device.workspace.selectedProfileId, isNull);
      expect(device.workspace.profiles, isEmpty);
      expect(device.workspace.notes, isEmpty);
      expect(device.workspace.privateSessionRevision, greaterThan(revision));
      device.syncRelease!.complete();
      await pendingSync;
      expect(device.workspace.notes, isEmpty);
      expect(device.workspace.registered, isFalse);
    },
  );

  test('disposed workspace rejects a queued attachment preview', () async {
    final cloud = _Cloud();
    final device = _Device(cloud);
    await device.workspace.initialize();
    await device.workspace.prepareNewBiometric();
    await device.workspace.confirmSetup();
    device.syncEntered = Completer<void>();
    device.syncRelease = Completer<void>();
    final heldSync = device.workspace.syncNow();
    await device.syncEntered!.future;
    final queuedPreview = device.workspace.readAttachmentPreview(
      SyncV2AttachmentReference(
        id: 'a' * 64,
        label: 'photo',
        type: 'photo',
        size: 1,
        sha256: 'b' * 64,
        chunks: ['blob_${'c' * 64}'],
      ),
    );
    device.workspace.dispose();
    device.syncRelease!.complete();
    await heldSync;
    await expectLater(queuedPreview, throwsA(isA<SyncV2WorkspaceException>()));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('two isolated workspaces enroll, transfer private files and resolve concurrent heads', () async {
    final cloud = _Cloud();
    final a = _Device(cloud), b = _Device(cloud);
    addTearDown(a.workspace.dispose);
    addTearDown(b.workspace.dispose);
    await a.workspace.initialize();
    await b.workspace.initialize();
    expect(a.workspace.registered, isFalse);
    final codes = await a.workspace.prepareNew('administrator password');
    expect(cloud.registryWrites, 0);
    expect(cloud.records, isEmpty);
    await a.workspace.confirmSetup();
    expect(a.workspace.registered, isTrue);
    expect(a.workspace.adminUnlocked, isTrue);
    expect(a.workspace.profiles.single.isNormal, isTrue);
    final normalId = a.workspace.selectedProfileId!;
    await a.workspace.saveNote(title: 'offline normal', body: 'cached body');
    await a.workspace.createProfile('Research', 'private password');
    final privateId = a.workspace.selectedProfileId!;
    final photo = Uint8List.fromList(
      List.generate(1024 * 1024 + 7, (i) => i % 251),
    );
    await a.workspace.saveNote(
      title: 'Secret',
      body: 'original',
      tags: [' Work ', '#work', 'private'],
      addedFiles: [
        SyncV2PendingAttachment(
          label: 'photo',
          type: AttachmentType.photo,
          bytes: photo,
        ),
      ],
    );
    await a.workspace.syncNow();
    await b.workspace.recover(codes.syncCode);
    expect(b.workspace.registered, isTrue);
    expect(b.workspace.profiles.length, 1);
    expect(b.workspace.notes.single.note.title, 'offline normal');
    await b.workspace.unlockPrivate('private password');
    expect(b.workspace.selectedProfileId, privateId);
    expect(b.workspace.notes.single.note.title, 'Secret');
    expect(b.workspace.notes.single.note.tags, ['Work', 'private']);
    await a.workspace.updateTag('work', replacement: 'Job');
    expect(a.workspace.notes.single.note.tags, ['Job', 'private']);
    await a.workspace.syncNow();
    await b.workspace.syncNow();
    expect(b.workspace.notes.single.note.tags, ['Job', 'private']);
    await a.workspace.updateTag('Job');
    expect(a.workspace.notes.single.note.tags, ['private']);
    await a.workspace.syncNow();
    await b.workspace.syncNow();
    expect(b.workspace.notes.single.note.tags, ['private']);
    await a.workspace.deleteNote(a.workspace.notes.single);
    await a.workspace.syncNow();
    await b.workspace.syncNow();
    expect(b.workspace.notes.single.isDeleted, isTrue);
    await b.workspace.restoreDeletedNote(b.workspace.notes.single);
    await b.workspace.syncNow();
    await a.workspace.syncNow();
    expect(a.workspace.notes.single.note.title, 'Secret');
    expect(a.workspace.notes.single.note.tags, ['private']);
    expect(
      await b.workspace.readAttachment(
        b.workspace.notes.single.attachments.single,
      ),
      photo,
    );
    final beforeArchive = a.workspace.notes.single.note;
    final archiveTarget = a.workspace.notes.single;
    await a.workspace.setNoteArchived(archiveTarget, archived: true);
    final archived = a.workspace.notes.single.note;
    expect(archived.archivedAt, isNotNull);
    expect(archived.title, beforeArchive.title);
    expect(archived.body, beforeArchive.body);
    expect(archived.tags, beforeArchive.tags);
    expect(archived.blocks, beforeArchive.blocks);
    expect(archived.attachments, beforeArchive.attachments);
    await a.workspace.syncNow();
    await b.workspace.syncNow();
    expect(b.workspace.notes.single.note.archivedAt, isNotNull);
    expect(b.workspace.notes.single.note.blocks, beforeArchive.blocks);
    expect(b.workspace.notes.single.note.tags, beforeArchive.tags);
    expect(
      await b.workspace.readAttachment(
        b.workspace.notes.single.attachments.single,
      ),
      photo,
    );
    await b.workspace.setNoteArchived(
      b.workspace.notes.single,
      archived: false,
    );
    expect(b.workspace.notes.single.note.archivedAt, isNull);
    await b.workspace.syncNow();
    await a.workspace.syncNow();
    expect(a.workspace.notes.single.note.archivedAt, isNull);
    final originalA = a.workspace.notes.single;
    final originalB = b.workspace.notes.single;
    await a.workspace.saveNote(
      original: originalA,
      title: 'A version',
      body: 'from a',
      blocks: [
        for (final block in originalA.note.blocks)
          block.type == NoteBlockType.paragraph
              ? block.copyWith(text: 'from a')
              : block,
      ],
    );
    await b.workspace.saveNote(
      original: originalB,
      title: 'B version',
      body: 'from b',
      blocks: [
        for (final block in originalB.note.blocks)
          block.type == NoteBlockType.paragraph
              ? block.copyWith(text: 'from b')
              : block,
      ],
    );
    await a.workspace.syncNow();
    await b.workspace.syncNow();
    await a.workspace.syncNow();
    expect(a.workspace.notes.single.isConflict, isTrue);
    expect(b.workspace.notes.single.isConflict, isTrue);
    final conflict = a.workspace.notes.single;
    await expectLater(
      a.workspace.setNoteArchived(conflict, archived: true),
      throwsA(isA<SyncV2WorkspaceException>()),
    );
    await expectLater(
      a.workspace.updateTag('private'),
      throwsA(isA<SyncV2WorkspaceException>()),
    );
    await expectLater(
      a.workspace.saveNote(original: conflict, title: 'merge', body: 'merged'),
      throwsA(isA<SyncV2WorkspaceException>()),
    );
    await expectLater(
      a.workspace.saveNote(
        original: conflict,
        selectedVersionId: conflict.versions.first.change.id,
        title: conflict.note.title,
        body: conflict.note.body,
        isPinned: true,
      ),
      throwsA(
        isA<SyncV2WorkspaceException>().having(
          (error) => error.code,
          'code',
          'conflict',
        ),
      ),
    );
    final selected = conflict.versions.singleWhere(
      (v) => (v.body!['note'] as Map)['title'] == 'B version',
    );
    final selectedNote = NoteEntry.fromJson(
      Map<String, dynamic>.from(selected.body!['note'] as Map),
    );
    final selectedAttachmentId =
        (selected.body!['attachments'] as List).single['id'] as String;
    await a.workspace.saveNote(
      original: conflict,
      selectedVersionId: selected.change.id,
      title: 'Resolved',
      body: 'from b',
      blocks: selectedNote.blocks
          .where((block) => block.type == NoteBlockType.paragraph)
          .toList(),
      removedAttachmentIds: [selectedAttachmentId],
    );
    expect(a.workspace.notes.single.isConflict, isFalse);
    expect(a.workspace.notes.single.attachments, isEmpty);
    expect(
      a.workspace.notes.single.note.blocks.any(
        (block) => block.type == NoteBlockType.photo,
      ),
      isFalse,
    );
    expect(a.workspace.notes.single.note.blocks.last.text, 'from b');
    await a.workspace.syncNow();
    await b.workspace.syncNow();
    expect(b.workspace.notes.single.note.title, 'Resolved');
    expect(b.workspace.notes.single.isConflict, isFalse);
    expect(b.workspace.notes.single.attachments, isEmpty);

    // Switching the selected profile limits note visibility without locking
    // other profiles that remain available in this session.
    await a.workspace.selectProfile(normalId);
    expect(a.workspace.profiles.any((p) => p.id == privateId), isTrue);
    expect(
      a.workspace.notes.every((entry) => entry.note.vaultId == normalId),
      isTrue,
    );
    await a.workspace.selectProfile(privateId);

    // Hold the operation queue, submit a brand-new private note, then lock
    // synchronously before the save starts. It must never borrow normal access.
    for (final useBackground in [false, true]) {
      if (b.workspace.selectedProfileId != privateId) {
        await b.workspace.resume();
        await b.workspace.unlockPrivate('private password');
      }
      final before = await b.inbox.readPage(
        generationId: b.workspace.generationId!,
        limit: 100,
      );
      b.syncEntered = Completer<void>();
      b.syncRelease = Completer<void>();
      final holding = b.workspace.syncNow();
      await b.syncEntered!.future;
      final save = b.workspace.saveNote(
        title: 'Queued private secret',
        body: 'must never enter normal notes',
        addedFiles: [
          SyncV2PendingAttachment(
            label: 'secret attachment',
            type: AttachmentType.file,
            bytes: Uint8List.fromList([71, 72, 73]),
          ),
        ],
      );
      final refused = expectLater(
        save,
        throwsA(isA<SyncV2WorkspaceException>()),
      );
      final queuedUnlockRefused = useBackground
          ? expectLater(
              b.workspace.unlockPrivate('private password'),
              throwsA(isA<SyncV2WorkspaceException>()),
            )
          : null;
      if (useBackground) {
        b.workspace.background();
      } else {
        b.workspace.lockPrivate();
      }
      b.syncRelease!.complete();
      await holding;
      await refused;
      if (queuedUnlockRefused != null) await queuedUnlockRefused;
      expect(b.workspace.profiles.length, 1);
      final after = await b.inbox.readPage(
        generationId: b.workspace.generationId!,
        limit: 100,
      );
      expect(after.map((r) => r.id).toSet(), before.map((r) => r.id).toSet());
      expect(
        await b.inbox.readOutbox(
          generationId: b.workspace.generationId!,
          limit: 100,
        ),
        isEmpty,
      );
      await b.workspace.resume();
      expect(b.workspace.notes.single.note.title, 'offline normal');
      expect(b.workspace.notes.single.note.body, 'cached body');
      expect(b.workspace.notes.single.attachments, isEmpty);
    }

    b.workspace.lockPrivate();
    await expectLater(
      b.workspace.recoverAdmin('invalid code', 'new administrator password'),
      throwsA(isA<SyncV2WorkspaceException>()),
    );
    expect(b.workspace.adminUnlocked, isFalse);
    await b.workspace.recoverAdmin(
      codes.adminCode,
      'new administrator password',
    );
    expect(b.workspace.adminUnlocked, isTrue);
    expect(b.workspace.profiles.any((p) => p.id == privateId), isTrue);

    // A delayed unlock cannot recreate private plaintext after an app lock.
    b.workspace.lockPrivate();
    b.store.unlockEntered = Completer<void>();
    b.store.unlockRelease = Completer<void>();
    final unlock = b.workspace.unlockPrivate('private password');
    final rejected = expectLater(
      unlock,
      throwsA(isA<SyncV2WorkspaceException>()),
    );
    await b.store.unlockEntered!.future;
    b.workspace.background();
    b.store.unlockRelease!.complete();
    await rejected;
    expect(b.workspace.profiles.length, 1);
    expect(b.workspace.notes, isEmpty);
    expect(b.workspace.adminUnlocked, isFalse);

    await b.workspace.resume();
    await b.workspace.unlockPrivate('private password');
    b.syncEntered = Completer<void>();
    b.syncRelease = Completer<void>();
    final syncing = b.workspace.syncNow();
    await b.syncEntered!.future;
    b.workspace.background();
    b.syncRelease!.complete();
    await syncing;
    expect(b.workspace.profiles.length, 1);
    expect(b.workspace.notes, isEmpty);
    expect(b.workspace.adminUnlocked, isFalse);

    // Cached registration restores normal data even if account/registry reads fail.
    cloud.offline = true;
    await a.workspace.initialize();
    expect(a.workspace.selectedProfileId, normalId);
    expect(a.workspace.notes.single.note.title, 'offline normal');
    expect(a.workspace.profiles.length, 1);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test(
    'five wrong passcodes delay the next unlock even when correct',
    () async {
      final device = _Device(_Cloud());
      addTearDown(device.workspace.dispose);
      final c = device.workspace;
      await c.initialize();
      await c.prepareNew('4321');
      await c.confirmSetup();
      await c.createProfile('Work', '1234');
      c.lockPrivate();
      for (var i = 0; i < 5; i++) {
        await expectLater(
          c.unlockPrivate('000$i'),
          throwsA(
            isA<SyncV2WorkspaceException>().having(
              (e) => e.code,
              'code',
              'wrong_password',
            ),
          ),
        );
      }
      await expectLater(
        c.unlockPrivate('1234'),
        throwsA(
          isA<SyncV2WorkspaceException>().having(
            (e) => e.code,
            'code',
            'throttled',
          ),
        ),
      );
    },
  );
}
