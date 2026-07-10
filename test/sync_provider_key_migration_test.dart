import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/home/presentation/home_providers.dart';
import 'package:himemo/features/security/data/encrypted_note_store.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/master_key_service.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:himemo/features/sync/data/google_drive_sync_transport.dart';
import 'package:himemo/features/sync/data/sync_bundle_key_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('post-auth Google Drive sync-key preparation', () {
    test('selecting Google Drive does not access Drive before auth', () async {
      final harness = await _SyncKeyHarness.create();
      addTearDown(harness.dispose);

      await harness.selectGoogleDrive();

      expect(harness.transport.totalReadCalls, 0);
      expect(harness.transport.legacyDeleteCalls, 0);
      expect(harness.keyFactoryCalls, 0);
      expect(await harness.storedSyncKey(), isNull);
    });

    test('authenticated empty Drive creates exactly one local key', () async {
      final harness = await _SyncKeyHarness.create();
      addTearDown(harness.dispose);

      final auth = await harness.connectGoogleDrive();

      expect(auth.stage, SyncAuthStage.authenticated, reason: auth.message);
      expect(harness.keyFactoryCalls, 1);
      expect(
        await harness.storedSyncKey(),
        base64Encode(List<int>.filled(32, _SyncKeyHarness.generatedKeyByte)),
      );
      expect(harness.transport.legacyReadCalls, 1);
      expect(harness.transport.bundleStatusReadCalls, 1);
      expect(harness.transport.attachmentHashReadCalls, 1);
      expect(harness.transport.bundleDownloadCalls, 0);
      expect(harness.transport.attachmentDownloadCalls, 0);

      await harness.container
          .read(syncProviderControllerProvider.notifier)
          .prepareGoogleDriveSyncKeyAfterAuthentication(
            accountId: _AuthenticatedSyncAuthGateway.accountId,
          );
      expect(
        harness.transport.totalReadCalls,
        3,
        reason: 'A prepared account should not be queried again.',
      );
      expect(harness.keyFactoryCalls, 1);
    });

    test(
      'empty Drive binds an existing local key without changing it',
      () async {
        final localBytes = List<int>.filled(32, 0x19);
        final harness = await _SyncKeyHarness.create();
        addTearDown(harness.dispose);
        await harness.secureStore.write(
          _SyncKeyHarness.syncKeyStorageKey,
          base64Encode(localBytes),
        );

        final auth = await harness.connectGoogleDrive();

        expect(auth.stage, SyncAuthStage.authenticated, reason: auth.message);
        expect(await harness.storedSyncKey(), base64Encode(localBytes));
        expect(harness.keyFactoryCalls, 0);
        expect(harness.transport.legacyReadCalls, 1);
        expect(harness.transport.bundleStatusReadCalls, 1);
        expect(harness.transport.attachmentHashReadCalls, 1);
        expect(harness.transport.bundleDownloadCalls, 0);
        expect(harness.transport.attachmentDownloadCalls, 0);

        await harness.container
            .read(syncProviderControllerProvider.notifier)
            .prepareGoogleDriveSyncKeyAfterAuthentication(
              accountId: _AuthenticatedSyncAuthGateway.accountId,
            );
        expect(harness.transport.totalReadCalls, 3);
        expect(await harness.storedSyncKey(), base64Encode(localBytes));
        expect(harness.keyFactoryCalls, 0);
      },
    );

    test('legacy Drive key is imported locally and then deleted', () async {
      final legacyCode = _backupCode(0x21);
      final harness = await _SyncKeyHarness.create(
        legacyBackupCodes: [legacyCode],
      );
      addTearDown(harness.dispose);

      final auth = await harness.connectGoogleDrive();

      expect(auth.stage, SyncAuthStage.authenticated, reason: auth.message);
      expect(
        await harness.storedSyncKey(),
        base64Encode(List<int>.filled(32, 0x21)),
      );
      expect(harness.keyFactoryCalls, 0);
      expect(harness.transport.legacyDeleteCalls, 1);
      expect(harness.transport.legacyBackupCodes, isEmpty);
      expect(harness.transport.bundleStatusReadCalls, 0);
      expect(harness.transport.attachmentHashReadCalls, 0);
    });

    test(
      'local and legacy key mismatch fails without changing either',
      () async {
        final localBytes = List<int>.filled(32, 0x31);
        final remoteCode = _backupCode(0x32);
        final harness = await _SyncKeyHarness.create(
          legacyBackupCodes: [remoteCode],
        );
        addTearDown(harness.dispose);
        await harness.secureStore.write(
          _SyncKeyHarness.syncKeyStorageKey,
          base64Encode(localBytes),
        );

        final auth = await harness.connectGoogleDrive();

        expect(auth.stage, SyncAuthStage.error);
        expect(auth.message, contains('different sync recovery key'));
        expect(await harness.storedSyncKey(), base64Encode(localBytes));
        expect(harness.transport.legacyBackupCodes, [remoteCode]);
        expect(harness.transport.legacyDeleteCalls, 0);
        expect(harness.keyFactoryCalls, 0);
        expect(harness.transport.bundleStatusReadCalls, 0);
      },
    );

    test('conflicting duplicate legacy keys fail without deletion', () async {
      final firstCode = _backupCode(0x41);
      final secondCode = _backupCode(0x42);
      final harness = await _SyncKeyHarness.create(
        legacyBackupCodes: [firstCode, secondCode],
      );
      addTearDown(harness.dispose);

      final auth = await harness.connectGoogleDrive();

      expect(auth.stage, SyncAuthStage.error);
      expect(auth.message, contains('conflicting legacy recovery keys'));
      expect(harness.transport.legacyBackupCodes, [firstCode, secondCode]);
      expect(harness.transport.legacyDeleteCalls, 0);
      expect(await harness.storedSyncKey(), isNull);
      expect(harness.keyFactoryCalls, 0);
      expect(harness.transport.bundleStatusReadCalls, 0);
    });

    test(
      'unknown remote encrypted bundle fails without generating a key',
      () async {
        const remoteStatus = RemoteSyncBundleStatus(
          fileId: 'unknown-key-bundle',
          fileName: 'himemo_sync_bundle.enc',
          bundleKind: SyncBundleKind.full,
        );
        final harness = await _SyncKeyHarness.create(
          remoteBundleStatus: remoteStatus,
          remoteBundlePayload: 'opaque-encrypted-payload',
        );
        addTearDown(harness.dispose);

        final auth = await harness.connectGoogleDrive();

        expect(auth.stage, SyncAuthStage.error);
        expect(auth.message, contains('already contains encrypted data'));
        expect(await harness.storedSyncKey(), isNull);
        expect(harness.keyFactoryCalls, 0);
        expect(harness.transport.legacyDeleteCalls, 0);
        expect(harness.transport.bundleStatusReadCalls, 1);
        expect(harness.transport.attachmentHashReadCalls, 1);
        expect(harness.transport.bundleDownloadCalls, 0);
      },
    );

    test('restored Google selection does not access Drive', () async {
      final harness = await _SyncKeyHarness.create(
        initialPreferences: const {'settings.sync_provider': 'googleDrive'},
      );
      addTearDown(harness.dispose);

      await _waitForProvider(
        harness.container,
        expected: SyncProvider.googleDrive,
      );

      expect(
        harness.container.read(syncProviderControllerProvider),
        SyncProvider.googleDrive,
      );
      expect(harness.transport.totalReadCalls, 0);
      expect(harness.transport.legacyDeleteCalls, 0);
      expect(harness.keyFactoryCalls, 0);
      expect(await harness.storedSyncKey(), isNull);
    });
  });
}

String _backupCode(int byte) {
  return '${SyncBundleKeyService.backupCodePrefix}'
      '${base64Encode(List<int>.filled(32, byte))}';
}

Future<void> _waitForProvider(
  ProviderContainer container, {
  required SyncProvider expected,
}) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (container.read(syncProviderControllerProvider) == expected) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Sync provider did not restore to ${expected.name}.');
}

Future<void> _settleAsyncRestores() async {
  for (var iteration = 0; iteration < 4; iteration++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _SyncKeyHarness {
  _SyncKeyHarness({
    required this.container,
    required this.secureStore,
    required this.encryptionService,
    required this.transport,
  });

  static const generatedKeyByte = 0x5a;
  static const syncKeyStorageKey = 'security.sync_bundle_key.v1';

  final ProviderContainer container;
  final MemorySecureKeyValueStore secureStore;
  final _TrackingEncryptionService encryptionService;
  final _TrackingGoogleDriveTransport transport;

  int get keyFactoryCalls => encryptionService.keyFactoryCalls;

  static Future<_SyncKeyHarness> create({
    List<String> legacyBackupCodes = const [],
    RemoteSyncBundleStatus? remoteBundleStatus,
    String? remoteBundlePayload,
    Set<String> remoteAttachmentHashes = const {},
    Map<String, Object> initialPreferences = const {},
  }) async {
    SharedPreferences.setMockInitialValues({
      'sync.integrity_approved.v1.googleDrive': true,
      ...initialPreferences,
    });
    final secureStore = MemorySecureKeyValueStore();
    final encryptionService = _TrackingEncryptionService();
    final masterKeyService = MasterKeyService(
      secureStore: secureStore,
      keyFactory: encryptionService.generateKeyBytes,
    );
    final noteStore = EncryptedNoteStore(
      encryptionService: encryptionService,
      masterKeyService: masterKeyService,
      isWeb: true,
      sharedPreferencesProvider: SharedPreferences.getInstance,
    );
    final transport = _TrackingGoogleDriveTransport(
      legacyBackupCodes: legacyBackupCodes,
      remoteBundleStatus: remoteBundleStatus,
      remoteBundlePayload: remoteBundlePayload,
      remoteAttachmentHashes: remoteAttachmentHashes,
    );
    final container = ProviderContainer(
      overrides: [
        secureKeyValueStoreProvider.overrideWithValue(secureStore),
        encryptionServiceProvider.overrideWithValue(encryptionService),
        encryptedNoteStoreProvider.overrideWithValue(noteStore),
        googleDriveSyncTransportProvider.overrideWithValue(transport),
        syncAuthGatewayProvider.overrideWithValue(
          _AuthenticatedSyncAuthGateway(),
        ),
      ],
    );
    container.read(syncProviderControllerProvider);
    await _settleAsyncRestores();
    return _SyncKeyHarness(
      container: container,
      secureStore: secureStore,
      encryptionService: encryptionService,
      transport: transport,
    );
  }

  Future<void> selectGoogleDrive() async {
    await container
        .read(syncProviderControllerProvider.notifier)
        .setProvider(SyncProvider.googleDrive);
  }

  Future<SyncAuthState> connectGoogleDrive() async {
    await selectGoogleDrive();
    container.read(syncAuthControllerProvider);
    await _settleAsyncRestores();
    await container
        .read(syncAuthControllerProvider.notifier)
        .connect(SyncProvider.googleDrive);
    return container.read(
      syncAuthControllerProvider,
    )[SyncProvider.googleDrive]!;
  }

  Future<String?> storedSyncKey() {
    return secureStore.read(syncKeyStorageKey);
  }

  void dispose() => container.dispose();
}

class _TrackingEncryptionService extends EncryptionService {
  int keyFactoryCalls = 0;

  @override
  List<int> generateKeyBytes({int length = 32}) {
    keyFactoryCalls++;
    return List<int>.filled(length, _SyncKeyHarness.generatedKeyByte);
  }
}

class _AuthenticatedSyncAuthGateway implements SyncAuthGateway {
  static const accountId = 'native-fake-google-user';

  @override
  Future<SyncAuthState> connect(SyncProvider provider) async {
    if (provider != SyncProvider.googleDrive) {
      return SyncAuthState.idle(provider);
    }
    return const SyncAuthState(
      provider: SyncProvider.googleDrive,
      stage: SyncAuthStage.authenticated,
      userId: accountId,
      displayName: 'Native fake Google user',
      email: 'native-fake@example.test',
    );
  }

  @override
  Future<void> disconnect(SyncProvider provider) async {}
}

class _TrackingGoogleDriveTransport
    implements GoogleDriveSyncTransport, LegacyGoogleDriveSyncKeyTransport {
  _TrackingGoogleDriveTransport({
    List<String> legacyBackupCodes = const [],
    this.remoteBundleStatus,
    this.remoteBundlePayload,
    Set<String> remoteAttachmentHashes = const {},
  }) : _legacyBackupCodes = List<String>.from(legacyBackupCodes),
       _remoteAttachmentHashes = Set<String>.from(remoteAttachmentHashes);

  final List<String> _legacyBackupCodes;
  final Set<String> _remoteAttachmentHashes;
  final RemoteSyncBundleStatus? remoteBundleStatus;
  final String? remoteBundlePayload;

  int legacyReadCalls = 0;
  int legacyDeleteCalls = 0;
  int bundleStatusReadCalls = 0;
  int attachmentHashReadCalls = 0;
  int bundleDownloadCalls = 0;
  int attachmentDownloadCalls = 0;

  List<String> get legacyBackupCodes =>
      List<String>.unmodifiable(_legacyBackupCodes);

  int get totalReadCalls =>
      legacyReadCalls +
      bundleStatusReadCalls +
      attachmentHashReadCalls +
      bundleDownloadCalls +
      attachmentDownloadCalls;

  @override
  Future<List<String>> fetchSyncKeyBackupCodes() async {
    legacyReadCalls++;
    return legacyBackupCodes;
  }

  @override
  Future<void> deleteSyncKeyBackupCode() async {
    legacyDeleteCalls++;
    _legacyBackupCodes.clear();
  }

  @override
  Future<RemoteSyncBundleStatus?> fetchLatestBundleStatus() async {
    bundleStatusReadCalls++;
    return remoteBundleStatus;
  }

  @override
  Future<Set<String>> listAttachmentObjectContentHashes() async {
    attachmentHashReadCalls++;
    return Set<String>.from(_remoteAttachmentHashes);
  }

  @override
  Future<DownloadedRemoteSyncBundle?> downloadLatestBundle() async {
    bundleDownloadCalls++;
    final status = remoteBundleStatus;
    final payload = remoteBundlePayload;
    if (status == null || payload == null) {
      return null;
    }
    return DownloadedRemoteSyncBundle(status: status, encodedPayload: payload);
  }

  @override
  Future<String?> downloadAttachmentObject(String contentHash) async {
    attachmentDownloadCalls++;
    return null;
  }

  @override
  Future<List<RemoteSyncBundleStatus>> listBundleHistory({int limit = 10}) {
    throw UnsupportedError('Not used by sync-key preparation tests.');
  }

  @override
  Future<DownloadedRemoteSyncBundle?> downloadBundleByFileId(String fileId) {
    throw UnsupportedError('Not used by sync-key preparation tests.');
  }

  @override
  Future<RemoteSyncBundleStatus> uploadBundle({
    required String encodedPayload,
    required String deviceId,
    required int noteCount,
    required int attachmentCount,
    String bundleKind = SyncBundleKind.full,
  }) {
    throw UnsupportedError('Not used by sync-key preparation tests.');
  }

  @override
  Future<void> uploadAttachmentObject({
    required String contentHash,
    required String encodedPayload,
    required String type,
    required String label,
    required int sizeBytes,
    bool skipExistingCheck = false,
  }) {
    throw UnsupportedError('Not used by sync-key preparation tests.');
  }
}
