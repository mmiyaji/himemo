import 'dart:async';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:himemo/features/security/data/sync_v2_biometric_key_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:himemo/features/sync/data/sync_v2_enrollment_store.dart';
import 'package:himemo/features/sync/data/sync_v2_generation_registration.dart';
import 'package:himemo/features/sync/data/sync_v2_header_codec.dart';
import 'package:himemo/features/sync/data/sync_v2_icloud_session.dart';
import 'package:himemo/features/sync/data/sync_v2_inbox.dart';
import 'package:himemo/features/sync/data/sync_v2_note_repository.dart';
import 'package:himemo/features/sync/data/sync_v2_payload_codec.dart';
import 'package:himemo/features/sync/data/sync_v2_publisher.dart';
import 'package:himemo/features/sync/data/sync_v2_receiver.dart';
import 'package:himemo/features/sync/data/sync_v2_pairing_code.dart';
import 'package:himemo/features/sync/presentation/sync_v2_workspace.dart';

class _Cloud
    implements
        SyncV2GenerationRegistrationTransport,
        SyncV2WriteTransport,
        SyncV2ReadTransport {
  String? proof;
  String account = 'account';
  bool offline = false;
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
    if (key.startsWith('sync.v2.profiles.') &&
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

  @override
  Future<void> delete(String key) => backing.delete(key);
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

class _Device {
  _Device(
    this.cloud, {
    _Store? sharedStore,
    _Biometrics? biometrics,
    bool Function()? settingsAdminAuthenticated,
  }) : store = sharedStore ?? _Store() {
    final encryption = EncryptionService();
    final headers = SyncV2HeaderCodec(encryption);
    inbox = SyncV2Inbox(NativeDatabase.memory(), headers);
    final repository = SyncV2NoteRepository(
      inbox,
      headers,
      SyncV2PayloadCodec(encryption),
    );
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
      activate: () async {
        activations++;
      },
      deactivate: () async {
        deactivations++;
      },
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
  int activations = 0, deactivations = 0;
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'generated recovery codes pair devices through role-specific QR codes',
    () async {
      final cloud = _Cloud();
      final first = _Device(cloud);
      addTearDown(first.workspace.dispose);
      await first.workspace.initialize();
      final codes = await first.workspace.prepareNewBiometric();
      await first.workspace.confirmSetup();

      final privateNote = NoteEntry(
        id: 'qr-paired-private-note',
        vaultId: 'private',
        title: 'QR paired private note',
        body: 'available only after administrator recovery',
        createdAt: DateTime.utc(2020),
      );
      final archive = Archive()
        ..addFile(
          ArchiveFile.string(
            'manifest.json',
            jsonEncode({
              'format': 'org.ruhenheim.himemo.notes.zip',
              'version': 1,
              'noteCount': 1,
              'attachmentCount': 0,
            }),
          ),
        )
        ..addFile(
          ArchiveFile.string(
            'notes.json',
            jsonEncode({
              'notes': [privateNote.toJson()],
            }),
          ),
        );
      await first.workspace.adminImportArchive(
        bytes: Uint8List.fromList(ZipEncoder().encode(archive)),
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

  test('settings admin session unlocks ZIP restore and setup stores a device grant', () async {
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
      c.enableAdminBiometrics(),
      throwsA(isA<SyncV2WorkspaceException>()),
    );
    expect(c.error, 'admin_required');

    final note = NoteEntry(
      id: 'settings-admin-private-note',
      vaultId: 'private',
      title: 'Restored through settings',
      body: 'private archive body',
      createdAt: DateTime.utc(2020),
    );
    final archive = Archive()
      ..addFile(
        ArchiveFile.string(
          'manifest.json',
          jsonEncode({
            'format': 'org.ruhenheim.himemo.notes.zip',
            'version': 1,
            'noteCount': 1,
            'attachmentCount': 0,
          }),
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'notes.json',
          jsonEncode({
            'notes': [note.toJson()],
          }),
        ),
      );
    await c.adminImportArchive(
      bytes: Uint8List.fromList(ZipEncoder().encode(archive)),
    );
    expect(c.profiles, hasLength(2));
    await c.selectProfile(c.profiles.singleWhere((p) => !p.isNormal).id);
    expect(c.notes.single.note.title, 'Restored through settings');
    expect(c.canManageAdminCredentials, isFalse);
    await expectLater(
      c.changeProfilePassword(c.selectedProfileId!, 'new-password-123'),
      throwsA(isA<SyncV2WorkspaceException>()),
    );
    await expectLater(
      c.repairProfilePassword(c.selectedProfileId!, 'new-password-123'),
      throwsA(isA<SyncV2WorkspaceException>()),
    );
    c.lockSettingsAdmin();
    expect(c.adminUnlocked, isFalse);
    expect(c.notes, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));

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

  test(
    'six character admin password is accepted and biometrics can be enabled',
    () async {
      final device = _Device(_Cloud());
      addTearDown(device.workspace.dispose);
      final c = device.workspace;
      await c.initialize();
      await expectLater(
        c.prepareNew('12345'),
        throwsA(isA<SyncV2WorkspaceException>()),
      );
      await c.prepareNew('123456');
      await c.confirmSetup();
      await c.enableAdminBiometrics();
      c.lockPrivate();
      await c.unlockAdminBiometric();
      expect(c.adminUnlocked, isTrue);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('admin bulk restore creates private destinations atomically and overwrites without private passwords', () async {
    final cloud = _Cloud();
    final first = _Device(cloud);
    addTearDown(first.workspace.dispose);
    final c = first.workspace;
    await c.initialize();
    final codes = await c.prepareNewBiometric();
    await c.confirmSetup();
    Uint8List zip(String title) {
      final entries = [
        NoteEntry(
          id: 'legacy-normal',
          vaultId: 'everyday',
          title: title,
          body: 'ZIP body',
          createdAt: DateTime.utc(2020),
          attachments: const [
            NoteAttachment(type: AttachmentType.photo, label: 'unlinked'),
          ],
        ),
        for (final source in [
          'private',
          'private_profile:old-two',
          'private_profile:old-three',
        ])
          NoteEntry(
            id: 'legacy-$source',
            vaultId: source,
            title: source,
            body: 'private ZIP body',
            createdAt: DateTime.utc(2020),
          ),
      ];
      return Uint8List.fromList(
        ZipEncoder().encode(
          Archive()
            ..addFile(
              ArchiveFile.string(
                'manifest.json',
                jsonEncode({
                  'format': 'org.ruhenheim.himemo.notes.zip',
                  'version': 1,
                  'noteCount': entries.length,
                  'attachmentCount': 0,
                }),
              ),
            )
            ..addFile(
              ArchiveFile.string(
                'notes.json',
                jsonEncode({
                  'notes': entries.map((note) => note.toJson()).toList(),
                }),
              ),
            ),
        ),
      );
    }

    // Even profile creation is rolled back if final ZIP validation fails.
    await expectLater(
      c.adminImportArchive(
        bytes: Uint8List.fromList([1]),
        inspection: SyncV2ArchiveInspection({'private': 1}, 0),
      ),
      throwsA(isA<SyncV2WorkspaceException>()),
    );
    expect(c.profiles, hasLength(1));
    expect(
      await first.inbox.readPage(generationId: c.generationId!, limit: 100),
      isEmpty,
    );
    final bytes = zip('Original ZIP');
    await c.adminImportArchive(bytes: bytes);
    expect(c.profiles, hasLength(4));
    final profileIds = c.profiles.map((p) => p.id).toSet();
    expect(c.notes.single.note.title, 'Original ZIP');
    expect(c.notes.single.note.attachments.single.filePath, isNull);
    await c.saveNote(
      original: c.notes.single,
      title: 'local edit',
      body: 'local edit',
    );
    await c.adminImportArchive(bytes: bytes);
    expect(c.notes.single.note.title, 'Original ZIP');
    final queued = (await first.inbox.readPage(
      generationId: c.generationId!,
      limit: 100,
    )).length;
    await c.adminImportArchive(bytes: bytes);
    expect(
      (await first.inbox.readPage(
        generationId: c.generationId!,
        limit: 100,
      )).length,
      queued,
    );
    await c.saveNote(title: 'Unrelated note', body: 'Keep this note');
    await c.adminImportArchive(bytes: zip('Changed ZIP'));
    expect(c.profiles.map((p) => p.id).toSet(), profileIds);
    expect(c.notes.map((n) => n.note.title).toSet(), {
      'Changed ZIP',
      'Unrelated note',
    });
    c.lockPrivate();
    await expectLater(
      c.adminImportArchive(bytes: bytes),
      throwsA(isA<SyncV2WorkspaceException>()),
    );
    expect(c.error, 'admin_required');
    await c.unlockAdminBiometric();
    await c.syncNow();
    final second = _Device(cloud);
    addTearDown(second.workspace.dispose);
    await second.workspace.initialize();
    await second.workspace.recover(codes.syncCode);
    expect(second.workspace.profiles, hasLength(1));
    await second.workspace.recoverAdminBiometric(codes.adminCode);
    expect(second.workspace.profiles.map((p) => p.id).toSet(), profileIds);
    for (final profile
        in second.workspace.profiles.where((p) => !p.isNormal).toList()) {
      await second.workspace.selectProfile(profile.id);
      expect(second.workspace.notes.single.note.body, 'private ZIP body');
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('concurrent administrator restores keep access when the same source has different labels', () async {
    final cloud = _Cloud();
    final first = _Device(cloud);
    final second = _Device(cloud);
    addTearDown(first.workspace.dispose);
    addTearDown(second.workspace.dispose);
    await first.workspace.initialize();
    final codes = await first.workspace.prepareNewBiometric();
    await first.workspace.confirmSetup();
    await second.workspace.initialize();
    await second.workspace.recover(codes.syncCode);
    await second.workspace.recoverAdminBiometric(codes.adminCode);
    Uint8List zip(List<String> sources) => Uint8List.fromList(
      ZipEncoder().encode(
        Archive()
          ..addFile(
            ArchiveFile.string(
              'manifest.json',
              jsonEncode({
                'format': 'org.ruhenheim.himemo.notes.zip',
                'version': 1,
                'noteCount': sources.length,
                'attachmentCount': 0,
              }),
            ),
          )
          ..addFile(
            ArchiveFile.string(
              'notes.json',
              jsonEncode({
                'notes': [
                  for (final source in sources)
                    NoteEntry(
                      id: 'legacy-$source',
                      vaultId: source,
                      title: source,
                      body: 'same private content',
                      createdAt: DateTime.utc(2020),
                    ).toJson(),
                ],
              }),
            ),
          ),
      ),
    );
    final full = zip(['private', 'private_profile:shared']);
    await first.workspace.adminImportArchive(bytes: full);
    final passwordProfile = first.workspace.profiles
        .where((p) => !p.isNormal)
        .last
        .id;
    await first.workspace.changeProfilePassword(
      passwordProfile,
      'user chosen private password',
    );
    await second.workspace.adminImportArchive(
      bytes: zip(['private_profile:shared']),
    );
    await first.workspace.syncNow();
    await second.workspace.syncNow();
    await first.workspace.syncNow();
    expect(first.workspace.adminUnlocked, isTrue);
    expect(second.workspace.adminUnlocked, isTrue);
    expect(first.workspace.profileConflicts, isNotEmpty);
    await first.workspace.adminImportArchive(bytes: full);
    await first.workspace.syncNow();
    await second.workspace.syncNow();
    expect(second.workspace.adminUnlocked, isTrue);
    expect(second.workspace.profileConflicts, isEmpty);
    expect(second.workspace.profiles, hasLength(3));
    for (final profile
        in second.workspace.profiles.where((p) => !p.isNormal).toList()) {
      await second.workspace.selectProfile(profile.id);
      expect(second.workspace.notes, hasLength(1));
      expect(second.workspace.notes.single.note.body, 'same private content');
    }
    second.workspace.lockPrivate();
    await second.workspace.unlockPrivate('user chosen private password');
    expect(
      second.workspace.profiles.where((p) => !p.isNormal).single.id,
      passwordProfile,
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

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
    expect(reopened.activations, 0);
    await reopened.workspace.resume();
    expect(reopened.workspace.registered, isTrue);
    expect(reopened.workspace.profiles.length, 1);
    expect(reopened.activations, 1);
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
  test('editing imported rich blocks exports updated text without removed attachment references', () async {
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
      filePath: 'attachments/photo',
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
    final input = Archive()
      ..addFile(
        ArchiveFile.string(
          'manifest.json',
          jsonEncode({
            'format': 'org.ruhenheim.himemo.notes.zip',
            'version': 1,
            'noteCount': 1,
            'attachmentCount': 1,
          }),
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'notes.json',
          jsonEncode({
            'notes': [rich.toJson()],
          }),
        ),
      )
      ..addFile(ArchiveFile.bytes('attachments/photo', [1, 2, 3]));
    await a.workspace.importArchive(
      bytes: Uint8List.fromList(ZipEncoder().encode(input)),
      destinations: {},
      acceptUnlinkedAttachments: false,
    );
    final imported = a.workspace.notes.single;
    expect(imported.note.blocks.map((block) => block.type), [
      NoteBlockType.paragraph,
      NoteBlockType.photo,
    ]);
    expect(imported.attachments, hasLength(1));
    await a.workspace.saveNote(
      original: imported,
      title: 'Edited rich note',
      body: 'Updated paragraph',
      removedAttachmentIds: [imported.attachments.single.id],
    );
    final updated = a.workspace.notes.single;
    expect(updated.note.body, 'Updated paragraph');
    expect(updated.note.blocks.map((block) => block.text), [
      'Updated paragraph',
    ]);
    expect(
      updated.note.blocks.any((block) => block.attachment != null),
      isFalse,
    );
    expect(updated.note.attachments, isEmpty);
    expect(updated.attachments, isEmpty);
    final exported = await a.workspace.exportArchive();
    final inspection = await a.workspace.inspectArchive(exported);
    expect(inspection.noteCountsByProfile, {'everyday': 1});
    expect(inspection.notesWithUnlinkedAttachments, 0);
    final decoded = ZipDecoder().decodeBytes(exported);
    expect(
      decoded.files.where((file) => file.name.startsWith('attachments/')),
      isEmpty,
    );
    final exportedJson = jsonDecode(
      utf8.decode(
        decoded.files.singleWhere((file) => file.name == 'notes.json').content,
      ),
    ) as Map;
    final exportedNote = NoteEntry.fromJson(
      Map<String, dynamic>.from((exportedJson['notes'] as List).single as Map),
    );
    expect(exportedNote.body, 'Updated paragraph');
    expect(exportedNote.blocks, [
      const NoteBlock(type: NoteBlockType.paragraph, text: 'Updated paragraph'),
    ]);
    expect(exportedNote.attachments, isEmpty);
    await b.workspace.recover(codes.syncCode);
    await b.workspace.importArchive(
      bytes: exported,
      destinations: {},
      acceptUnlinkedAttachments: false,
    );
    final roundTripped = b.workspace.notes.single;
    expect(roundTripped.note.body, 'Updated paragraph');
    expect(roundTripped.note.blocks, exportedNote.blocks);
    expect(roundTripped.attachments, isEmpty);
    expect(roundTripped.note.attachments, isEmpty);
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
    expect(a.activations, 0);
    await a.workspace.confirmSetup();
    expect(a.workspace.registered, isTrue);
    expect(a.workspace.adminUnlocked, isTrue);
    expect(a.activations, 1);
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
    expect(b.activations, 1);
    expect(b.workspace.profiles.length, 1);
    expect(b.workspace.notes.single.note.title, 'offline normal');
    await b.workspace.unlockPrivate('private password');
    expect(b.workspace.selectedProfileId, privateId);
    expect(b.workspace.notes.single.note.title, 'Secret');
    expect(
      await b.workspace.readAttachment(
        b.workspace.notes.single.attachments.single,
      ),
      photo,
    );
    final originalA = a.workspace.notes.single;
    final originalB = b.workspace.notes.single;
    await a.workspace.saveNote(
      original: originalA,
      title: 'A version',
      body: 'from a',
    );
    await b.workspace.saveNote(
      original: originalB,
      title: 'B version',
      body: 'from b',
    );
    await a.workspace.syncNow();
    await b.workspace.syncNow();
    await a.workspace.syncNow();
    expect(a.workspace.notes.single.isConflict, isTrue);
    expect(b.workspace.notes.single.isConflict, isTrue);
    final conflict = a.workspace.notes.single;
    await expectLater(
      a.workspace.saveNote(original: conflict, title: 'merge', body: 'merged'),
      throwsA(isA<SyncV2WorkspaceException>()),
    );
    final selected = conflict.versions.singleWhere(
      (v) => (v.body!['note'] as Map)['title'] == 'B version',
    );
    await a.workspace.saveNote(
      original: conflict,
      selectedVersionId: selected.change.id,
      title: 'Resolved',
      body: 'from b',
    );
    expect(a.workspace.notes.single.isConflict, isFalse);
    expect(a.workspace.notes.single.attachments.length, 1);
    await a.workspace.syncNow();
    await b.workspace.syncNow();
    expect(b.workspace.notes.single.note.title, 'Resolved');
    expect(b.workspace.notes.single.isConflict, isFalse);

    // Export authorization follows the selected profile even while another
    // private profile remains unlocked in the workspace.
    await a.workspace.selectProfile(normalId);
    expect(a.workspace.profiles.any((p) => p.id == privateId), isTrue);
    final normalArchive = await a.workspace.exportArchive();
    final exported = await a.workspace.inspectArchive(normalArchive);
    expect(exported.noteCountsByProfile, {'everyday': 1});
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
    expect(a.activations, 2);
    expect(a.deactivations, 0);
    await a.workspace.leaveV2();
    expect(a.deactivations, 1);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
