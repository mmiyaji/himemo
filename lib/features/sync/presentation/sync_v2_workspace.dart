import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../home/domain/note_entry.dart';
import '../../home/domain/note_tags.dart';
import '../../home/presentation/home_providers.dart';
import '../../security/data/authentication_throttle.dart';
import '../../security/data/encryption_service.dart';
import '../../security/data/secure_key_value_store.dart';
import '../../security/data/sync_v2_admin_store.dart';
import '../../security/data/sync_v2_device_admin_store.dart';
import '../../security/data/sync_v2_biometric_key_store.dart';
import '../../security/data/sync_v2_profile_keys.dart';
import '../data/sync_v2_archive_service.dart';
import '../data/sync_v2_capture_service.dart';
import '../data/sync_v2_attachment_service.dart';
import '../data/sync_v2_enrollment_store.dart';
import '../data/sync_v2_generation_registration.dart';
import '../data/sync_v2_header_codec.dart';
import '../data/sync_v2_icloud_session.dart';
import '../data/sync_v2_icloud_transport.dart';
import '../data/sync_v2_inbox.dart';
import '../data/sync_v2_note_repository.dart';
import '../data/sync_v2_note_store.dart';
import '../data/sync_v2_payload_codec.dart';
import '../data/sync_v2_profile_catalog.dart';

export '../data/sync_v2_archive_service.dart' show SyncV2ArchiveInspection;
export '../data/sync_v2_attachment_service.dart' show SyncV2AttachmentReference;

const syncV2EnabledPreference = 'settings.sync_v2.enabled';

/// Preserve the persisted legacy selection across interrupted activation.
Future<void> activateSyncV2Preference(
  SharedPreferences prefs,
  Future<void> Function() suspendLegacy,
) async {
  const previousKey = 'settings.sync_v2.previous_provider';
  const pendingKey = 'settings.sync_v2.activation_pending';
  if (prefs.getBool(syncV2EnabledPreference) != true &&
      prefs.getBool(pendingKey) != true) {
    final previous =
        prefs.getString('settings.sync_provider') ?? SyncProvider.off.name;
    if (!await prefs.setString(previousKey, previous) ||
        !await prefs.setBool(pendingKey, true)) {
      throw StateError('Could not preserve legacy sync selection');
    }
  }
  await suspendLegacy();
  if (!await prefs.setBool(syncV2EnabledPreference, true)) {
    throw StateError('Could not select v2');
  }
  await prefs.remove(pendingKey);
}

const syncV2MaxPendingAttachmentBytes = 128 * 1024 * 1024;

String syncV2EditableBody(NoteEntry note) {
  final paragraphs = note.blocks
      .where(
        (block) => block.type == NoteBlockType.paragraph && block.text != null,
      )
      .map((block) => block.text!)
      .toList();
  return paragraphs.isEmpty ? note.body : paragraphs.join('\n\n');
}

final syncV2WorkspaceProvider = Provider<SyncV2WorkspaceController>((ref) {
  final encryption = EncryptionService();
  final store = ref.read(secureKeyValueStoreProvider);
  final enrollments = SyncV2EnrollmentStore(store);
  final headers = SyncV2HeaderCodec(encryption);
  final inbox = SyncV2Inbox.open(headers);
  final workspace = SyncV2WorkspaceController(
    inbox: inbox,
    repository: SyncV2NoteRepository(
      inbox,
      headers,
      SyncV2PayloadCodec(encryption),
    ),
    store: store,
    enrollments: enrollments,
    registrationTransport: SyncV2ICloudGenerationRegistrationTransport(
      SyncV2ICloudTransport(accountId: ''),
    ),
    // Each operation is rebound to the checked account, never to an old account.
    registrationFactory: (account) => SyncV2GenerationRegistration(
      SyncV2ICloudGenerationRegistrationTransport(
        SyncV2ICloudTransport(accountId: account),
      ),
      enrollments,
    ),
    syncOperation: () => SyncV2ICloudSession(
      enrollments,
      inbox,
      stopOnQuarantine: true,
    ).syncOnce(),
    activate: () async {
      final prefs = await SharedPreferences.getInstance();
      await activateSyncV2Preference(
        prefs,
        () => ref
            .read(syncTransferControllerProvider.notifier)
            .suspendLegacyForV2(),
      );
    },
    deactivate: () async {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.remove('settings.sync_v2.activation_pending')) {
        throw StateError('Could not clear pending v2 activation');
      }
      if (!await prefs.setBool(syncV2EnabledPreference, false)) {
        throw StateError('Could not select legacy workspace');
      }
      final previous = prefs.getString('settings.sync_v2.previous_provider');
      if (previous != null) {
        final provider = SyncProvider.values
            .where((provider) => provider.name == previous)
            .firstOrNull;
        if (provider != null) {
          await ref
              .read(syncProviderControllerProvider.notifier)
              .setProvider(provider);
        }
      }
    },
    settingsAdminAuthenticated: () =>
        ref.read(adminModeSessionControllerProvider),
    deviceAdminStore: SyncV2DeviceAdminStore(
      FlutterSecureKeyValueStore(
        iOptions: const IOSOptions(
          accountName: 'org.ruhenheim.himemo.sync_v2_device_admin',
          accessibility: KeychainAccessibility.unlocked_this_device,
        ),
      ),
      installationId: _syncV2AdminInstallationId,
    ),
    supported: !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS,
  );
  ref.listen<bool>(adminModeSessionControllerProvider, (previous, current) {
    if (!current) workspace.lockSettingsAdmin();
  });
  ref.onDispose(workspace.dispose);
  return workspace;
});

Future<String?> _syncV2AdminInstallationId(bool create) async {
  final preferences = await SharedPreferences.getInstance();
  const key = 'security.sync_v2.admin_installation.v1';
  final existing = preferences.getString(key);
  if (existing != null && RegExp(r'^[0-9a-f]{64}$').hasMatch(existing)) {
    return existing;
  }
  if (!create) return null;
  final generated = EncryptionService()
      .generateKeyBytes()
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  if (!await preferences.setString(key, generated)) {
    throw StateError('Could not persist administrator installation identity');
  }
  return generated;
}

class SyncV2WorkspaceProfile {
  const SyncV2WorkspaceProfile(this.id, this.name, {this.isNormal = false});
  final String id, name;
  final bool isNormal;
}

class SyncV2PendingAttachment {
  const SyncV2PendingAttachment({
    required this.label,
    required this.type,
    required this.bytes,
    this.draftId,
  });
  final String label;
  final AttachmentType type;
  final Uint8List bytes;

  /// In-memory identity only; saveNote must replace it with an encrypted ref.
  final String? draftId;
}

class SyncV2WorkspaceNote {
  SyncV2WorkspaceNote(
    this.note,
    this.snapshot,
    this.attachments, {
    this.isCorrupt = false,
  });
  final NoteEntry note;
  final SyncV2NoteSnapshot snapshot;
  final List<SyncV2AttachmentReference> attachments;
  final bool isCorrupt;
  bool get readOnly => isCorrupt;
  Set<String> get headIds => snapshot.headIds;
  List<SyncV2NoteVersion> get versions => snapshot.versions;
  bool get isConflict => snapshot.hasConflict;
  bool get isDeleted =>
      versions.isNotEmpty && versions.every((v) => v.isDeleted);
  bool get ready => !isCorrupt && snapshot.canCompareVersions;
}

class SyncV2WorkspaceException implements Exception {
  const SyncV2WorkspaceException(this.code);
  final String code;
  @override
  String toString() => code;
}

/// Owns unlocked keys and plaintext projections for the dedicated v2 workspace.
/// All mutations and sync passes are serialized; no legacy notes are written.
class SyncV2WorkspaceController extends ChangeNotifier {
  SyncV2WorkspaceController({
    required this.inbox,
    required this.repository,
    required this.store,
    required this.enrollments,
    required this.registrationTransport,
    required this.registrationFactory,
    required this.syncOperation,
    required this.activate,
    required this.deactivate,
    required this.supported,
    SyncV2BiometricKeyStore? biometricStore,
    SyncV2DeviceAdminStore? deviceAdminStore,
    bool Function()? settingsAdminAuthenticated,
    bool automaticSync = true,
  }) : biometrics = biometricStore ?? MethodChannelSyncV2BiometricKeyStore(),
       deviceAdminStore = deviceAdminStore ?? SyncV2DeviceAdminStore(store),
       _settingsAdminAuthenticated =
           settingsAdminAuthenticated ?? (() => false) {
    if (automaticSync) {
      _timer = Timer.periodic(const Duration(seconds: 60), (_) {
        if (registered && !_paused && !busy) {
          unawaited(syncNow().catchError((Object _) {}));
        }
      });
    }
  }
  final SyncV2BiometricKeyStore biometrics;
  final SyncV2DeviceAdminStore deviceAdminStore;
  final bool Function() _settingsAdminAuthenticated;
  bool _adminFromSettings = false;
  int _settingsAdminRevision = 0;
  bool get settingsAdminActive => _settingsAdminAuthenticated();
  bool get canManageAdminCredentials => adminUnlocked && !_adminFromSettings;

  void lockSettingsAdmin() {
    _settingsAdminRevision++;
    if (_adminFromSettings) lockPrivate();
  }

  Future<void> _rememberDeviceAdmin(SecretKey key, int epoch) =>
      _saveDeviceAdmin(key, epoch, accountId!, generationId!);

  Future<void> _saveDeviceAdmin(
    SecretKey key,
    int epoch,
    String account,
    String generation,
  ) async {
    if (_paused || _disposed || epoch != _epoch) {
      throw const SyncV2WorkspaceException('locked');
    }
    try {
      await deviceAdminStore.save(
        accountId: account,
        generationId: generation,
        adminKey: key,
      );
    } catch (_) {
      // This optional shortcut must not prevent the original v2 credential
      // from opening the workspace when Keychain persistence is unavailable.
    }
    if (_paused || _disposed || epoch != _epoch) {
      throw const SyncV2WorkspaceException('locked');
    }
  }

  /// A device-authenticated settings session may use this device's v2 key.
  /// SYNC-only enrollment never creates this grant. Older installs return false
  /// until a v2 password, biometric or ADMIN unlock has established the grant.
  Future<bool> unlockAdminFromSettings() => _run(() async {
    if (!settingsAdminActive || !registered) {
      throw const SyncV2WorkspaceException('admin_required');
    }
    final epoch = _epoch;
    final revision = _settingsAdminRevision;
    SecretKey? admin;
    var profilesInstalled = false;
    try {
      admin = await deviceAdminStore.read(
        accountId: accountId!,
        generationId: generationId!,
      );
      if (admin == null) return false;
      await _registration.verifyAdminKey(
        accountId: accountId!,
        adminKey: admin,
      );
      void checkSession() {
        if (!settingsAdminActive ||
            revision != _settingsAdminRevision ||
            _paused ||
            _disposed ||
            epoch != _epoch) {
          throw const SyncV2WorkspaceException('locked');
        }
      }

      checkSession();
      await _refreshAdminProfiles(admin, epoch);
      profilesInstalled = true;
      checkSession();
      _admin?.destroy();
      _admin = admin;
      _adminFromSettings = true;
      await _reloadNotes();
      return true;
    } catch (failure) {
      if (profilesInstalled && epoch == _epoch) lockPrivate();
      admin?.destroy();
      if (failure is SyncV2WorkspaceException && failure.code == 'locked') {
        rethrow;
      }
      if (failure is FormatException || failure is HimemoDecryptionException) {
        try {
          await deviceAdminStore.delete(
            accountId: accountId!,
            generationId: generationId!,
          );
        } catch (_) {
          // A failed shortcut still falls back to the original credential.
        }
      }
      return false;
    }
  });
  bool biometricsAvailable = false, biometricEnabled = false;
  bool biometricAuthenticating = false;
  bool _preparedBiometric = false;
  bool get preparedUsesBiometrics => _preparedBiometric;

  Future<T> _authenticateBiometric<T>(Future<T> Function() action) async {
    biometricAuthenticating = true;
    _notify();
    try {
      return await action();
    } finally {
      biometricAuthenticating = false;
      _notify();
    }
  }

  final SyncV2Inbox inbox;
  final SyncV2NoteRepository repository;
  final SecureKeyValueStore store;
  final SyncV2EnrollmentStore enrollments;
  final SyncV2GenerationRegistrationTransport registrationTransport;
  final SyncV2GenerationRegistration Function(String account)
  registrationFactory;
  final Future<SyncV2ICloudProgress> Function() syncOperation;
  final Future<void> Function() activate, deactivate;
  final bool supported;
  final _encryption = EncryptionService();
  Timer? _timer;
  Future<void> _tail = Future.value();
  bool _disposed = false, _paused = false;
  int _epoch = 0;
  bool loading = true, busy = false, registered = false, hasPending = false;
  String? error, diagnosticCode, accountId, generationId, selectedProfileId;
  SyncV2UnlockedProfileKey? _normal;
  SecretKey? _syncKey, _admin;
  SyncV2PreparedRegistration? _prepared;
  SecretKey? _setupAdmin;
  final _private = <String, SyncV2UnlockedProfile>{};
  List<SyncV2WorkspaceNote> notes = [];
  List<SyncV2WorkspaceProfile> profileConflicts = [];
  List<({String id, String phase, String reason, int attempts, int? retryAt})>
  failures = [];
  bool get adminUnlocked => _admin != null;

  /// Changes whenever unlocked projections must be discarded by the UI.
  int get privateSessionRevision => _epoch;
  bool get hasPreparedSetup => _prepared != null;

  /// Keys for the v1 UI note store. Null until registered and while paused.
  SyncV2NoteStoreSession? get noteStoreSession {
    final normal = _normal, syncKey = _syncKey, generation = generationId;
    if (!registered || _paused || _disposed) return null;
    if (normal == null || syncKey == null || generation == null) return null;
    return SyncV2NoteStoreSession(
      generationId: generation,
      syncKey: syncKey,
      normalProfileId: normal.profileId,
      profiles: {
        normal.profileId: normal,
        for (final profile in _private.values) profile.id: profile.access,
      },
    );
  }

  List<SyncV2WorkspaceProfile> get profiles => [
    if (_normal != null)
      SyncV2WorkspaceProfile(_normal!.profileId, '通常', isNormal: true),
    for (final profile in _private.values)
      SyncV2WorkspaceProfile(profile.id, profile.name),
  ];
  SyncV2GenerationRegistration get _registration =>
      registrationFactory(accountId!);
  SyncV2AdminStore get _adminStore =>
      SyncV2AdminStore(store, _encryption, generationId: generationId!);
  SyncV2ProfileCatalog get _catalog => SyncV2ProfileCatalog(
    inbox,
    repository,
    _encryption,
    store,
    generationId: generationId!,
    syncKey: _syncKey!,
    normalAccess: _normal!,
  );
  SyncV2UnlockedProfileKey get _selected {
    if (selectedProfileId == _normal?.profileId) return _normal!;
    final profile = _private[selectedProfileId];
    if (profile == null) throw const SyncV2WorkspaceException('locked');
    return profile.access;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  String _id(String prefix) =>
      '${prefix}_${_encryption.generateKeyBytes(length: 16).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';

  Future<T> _run<T>(
    Future<T> Function() operation, {
    bool allowPaused = false,
  }) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      if (_disposed) {
        result.completeError(const SyncV2WorkspaceException('closed'));
        return;
      }
      if (_paused && !allowPaused) {
        result.completeError(const SyncV2WorkspaceException('locked'));
        return;
      }
      busy = true;
      error = null;
      diagnosticCode = null;
      _notify();
      try {
        result.complete(await operation());
      } catch (failure) {
        if (failure is SyncV2RegistrationFailure) {
          diagnosticCode = '${failure.stage.name}/${failure.safeCode}';
        } else if (failure is PlatformException &&
            RegExp(r'^[0-9]{1,2}$').hasMatch(failure.code)) {
          diagnosticCode = 'cloudkit/${failure.code}';
        }
        error = switch (failure) {
          AuthenticationThrottledException() => 'throttled',
          SyncV2StaleNote() => 'conflict',
          SyncV2CloudDataDeleted() => 'cloud_deleted',
          SyncV2RegistrationConflict() => 'registration_conflict',
          SyncV2WorkspaceException(:final code) => code,
          PlatformException(:final code) => _platformError(code),
          SyncV2RegistrationFailure(:final safeCode) => _platformError(
            safeCode,
          ),
          _ => 'operation_failed',
        };
        result.completeError(SyncV2WorkspaceException(error!));
      } finally {
        busy = false;
        loading = false;
        _notify();
      }
    });
    return result.future;
  }

  String _platformError(String code) => switch (code) {
    'cancelled' => 'authentication_cancelled',
    'unavailable' || 'invalidated' => 'biometric_unavailable',
    '9' || 'not_authenticated' => 'icloud_account',
    '3' || '4' || '6' || '7' || '23' => 'icloud_network',
    '5' || '8' || '10' || '12' || '15' => 'icloud_permission',
    '25' => 'icloud_quota',
    'cloudkit_v2_accountChanged' => 'account_changed',
    _ => 'operation_failed',
  };

  Future<void> initialize() => _run(_initialize, allowPaused: true);
  Future<void> _initialize() async {
    if (!supported) return;
    _paused = false;
    try {
      biometricsAvailable = await biometrics.isAvailable();
    } catch (_) {
      biometricsAvailable = false;
    }
    String account;
    try {
      account = await registrationTransport.readCurrentAccountId();
    } catch (_) {
      final cached = await store.read('security.sync_v2.current_account');
      if (cached == null) rethrow;
      account = cached;
    }
    _checkAccountIdentity(account);
    final pending = await enrollments.readPendingRegistration();
    hasPending = pending != null;
    pending?.syncKey.destroy();
    final enrollment = await enrollments.readForAccount(account);
    if (enrollment == null) return;
    enrollment.syncKey.destroy();
    final normal = await registrationFactory(account)
        .restoreEnrolled(accountId: account);
    await _attach(normal, account: account);
    _discardPrepared();
  }

  void _checkAccountIdentity(String account) {
    if (registered && accountId != account) {
      lockPrivate();
      throw const SyncV2WorkspaceException('account_changed');
    }
  }

  Future<void> _attach(
    SyncV2RegisteredNormalProfile normal, {
    required String account,
  }) async {
    if (_paused || _disposed) {
      normal.destroy();
      throw const SyncV2WorkspaceException('locked');
    }
    final epoch = _epoch;
    final enrollment = await enrollments.readForAccount(account);
    if (_paused || _disposed || epoch != _epoch) {
      normal.destroy();
      enrollment?.syncKey.destroy();
      throw const SyncV2WorkspaceException('locked');
    }
    if (enrollment == null) {
      normal.destroy();
      throw StateError('Missing enrollment');
    }
    lockPrivate();
    final attachedEpoch = _epoch;
    _normal?.destroy();
    _syncKey?.destroy();
    _normal = normal.access;
    accountId = account;
    _syncKey = enrollment.syncKey;
    generationId = enrollment.generationId;
    biometricEnabled =
        await store.read('sync.v2.biometric.$generationId') == 'enabled';
    selectedProfileId = normal.profileId;
    registered = false;
    hasPending = false;
    _paused = false;
    await store.write('security.sync_v2.current_account', accountId!);
    if (_paused || _disposed || attachedEpoch != _epoch) {
      throw const SyncV2WorkspaceException('locked');
    }
    await activate();
    if (_paused || _disposed || attachedEpoch != _epoch) {
      throw const SyncV2WorkspaceException('locked');
    }
    registered = true;
    await _reloadNotes();
    if (_paused || _disposed) throw const SyncV2WorkspaceException('locked');
  }

  Future<({String syncCode, String adminCode})> prepareNew(
    String adminPassword,
  ) => _prepareNew(adminPassword: adminPassword);

  Future<({String syncCode, String adminCode})> prepareNewBiometric() =>
      _prepareNew(useBiometrics: true);

  Future<({String syncCode, String adminCode})> _prepareNew({
    String? adminPassword,
    bool useBiometrics = false,
  }) => _run(() async {
    if (!supported ||
        registered ||
        (!useBiometrics &&
            (adminPassword == null ||
                adminPassword.length <
                    SyncV2AdminStore.minimumPasswordLength))) {
      throw const SyncV2WorkspaceException('invalid_input');
    }
    final epoch = _epoch;
    final account = await registrationTransport.readCurrentAccountId();
    final enrolled = await enrollments.readForAccount(account);
    if (enrolled != null) {
      enrolled.syncKey.destroy();
      throw const SyncV2WorkspaceException('already_registered');
    }
    final existing = _prepared;
    if (existing != null) {
      if (existing.accountId != account) {
        throw const SyncV2WorkspaceException('account_changed');
      }
      final adminStore = SyncV2AdminStore(
        store,
        _encryption,
        generationId: existing.generationId,
      );
      if (useBiometrics != _preparedBiometric) {
        throw const SyncV2WorkspaceException('invalid_input');
      }
      final admin = useBiometrics
          ? await _authenticateBiometric(
              () => biometrics.read(existing.generationId),
            )
          : await adminStore.unlock(adminPassword!);
      if (admin == null) throw const SyncV2WorkspaceException('wrong_password');
      if (epoch != _epoch || _paused) {
        admin.destroy();
        throw const SyncV2WorkspaceException('locked');
      }
      _setupAdmin?.destroy();
      _setupAdmin = admin;
      return (
        syncCode: existing.recoveryCode,
        adminCode: await adminStore.encodeRecoveryCode(admin),
      );
    }
    final admin = SecretKey(_encryption.generateKeyBytes());
    SyncV2PreparedRegistration? prepared;
    try {
      prepared = await registrationFactory(account)
          .prepare(accountId: account, adminKey: admin);
      final adminStore = SyncV2AdminStore(
        store,
        _encryption,
        generationId: prepared.generationId,
      );
      if (useBiometrics) {
        await _authenticateBiometric(
          () => biometrics.save(prepared!.generationId, admin),
        );
        await store.write(
          'sync.v2.biometric.${prepared.generationId}',
          'enabled',
        );
      } else {
        await adminStore.configure(adminKey: admin, password: adminPassword!);
      }
      await _saveDeviceAdmin(admin, epoch, account, prepared.generationId);
      final adminCode = await adminStore.encodeRecoveryCode(admin);
      if (epoch != _epoch) throw const SyncV2WorkspaceException('locked');
      _prepared?.destroy();
      _setupAdmin?.destroy();
      _prepared = prepared;
      _preparedBiometric = useBiometrics;
      accountId = account;
      _setupAdmin = admin;
      return (syncCode: prepared.recoveryCode, adminCode: adminCode);
    } catch (_) {
      prepared?.destroy();
      admin.destroy();
      rethrow;
    }
  });

  Future<void> confirmSetup() => _run(() async {
    final prepared = _prepared;
    if (prepared == null) throw const SyncV2WorkspaceException('invalid_input');
    late SyncV2RegisteredNormalProfile normal;
    try {
      normal = await registrationFactory(prepared.accountId)
          .publishPrepared(prepared);
    } finally {
      final pending = await enrollments.readPendingRegistration();
      hasPending = pending != null;
      pending?.syncKey.destroy();
    }
    await _attach(normal, account: prepared.accountId);
    if (_setupAdmin != null) await _rememberDeviceAdmin(_setupAdmin!, _epoch);
    _admin = _setupAdmin;
    _adminFromSettings = false;
    _setupAdmin = null;
    prepared.destroy();
    _prepared = null;
  });
  void _discardPrepared() {
    _prepared?.destroy();
    _prepared = null;
    _setupAdmin?.destroy();
    _setupAdmin = null;
  }

  Future<void> cancelSetup() => _run(() async {
    _discardPrepared();
  }, allowPaused: true);

  Future<void> resumePending() => _run(() async {
    final account = await registrationTransport.readCurrentAccountId();
    _checkAccountIdentity(account);
    await _attach(
      await registrationFactory(account).resumePending(),
      account: account,
    );
  });
  Future<void> recover(String code) => _run(() async {
    final account = await registrationTransport.readCurrentAccountId();
    _checkAccountIdentity(account);
    await _attach(
      await registrationFactory(account).recover(code),
      account: account,
    );
    await _sync();
  });
  Future<void> selectProfile(String id) => _run(() async {
    _paused = false;
    if (!profiles.any((p) => p.id == id)) {
      throw const SyncV2WorkspaceException('locked');
    }
    selectedProfileId = id;
    await _reloadNotes();
  });
  Future<void> resume() => _run(() async {
    _paused = false;
    if (registered) {
      await _reloadNotes();
    } else {
      await _initialize();
    }
  }, allowPaused: true);

  Future<void> captureShared({
    required String rawText,
    required String requestId,
    required Future<List<SyncV2CaptureFile>> Function() readFiles,
  }) => _run(() async {
    if (!registered || _normal == null) {
      throw const SyncV2WorkspaceException('locked');
    }
    await SyncV2CaptureService(inbox, repository).capture(
      generationId: generationId!,
      syncKey: _syncKey!,
      normalAccess: _normal!,
      rawText: rawText,
      requestId: requestId,
      readFiles: readFiles,
    );
    if (selectedProfileId == _normal!.profileId) await _reloadNotes();
  });

  void lockPrivate() {
    _epoch++;
    for (final profile in _private.values) {
      profile.destroy();
    }
    _private.clear();
    profileConflicts = [];
    _admin?.destroy();
    _admin = null;
    _adminFromSettings = false;
    selectedProfileId = _normal?.profileId;
    notes = [];
    _notify();
  }

  void background() {
    _paused = true;
    lockPrivate();
    _setupAdmin?.destroy();
    _setupAdmin = null;
  }

  /// Immediately revoke the current session after an external sign-out.
  /// Unlike backgrounding, this also releases the normal profile and sync key.
  void revokeSession() {
    if (_disposed) return;
    background();
    _discardPrepared();
    _normal?.destroy();
    _normal = null;
    _syncKey?.destroy();
    _syncKey = null;
    accountId = null;
    generationId = null;
    selectedProfileId = null;
    registered = false;
    hasPending = false;
    biometricEnabled = false;
    failures = [];
    _notify();
  }

  void _installProfiles(List<SyncV2UnlockedProfile> unlocked, int epoch) {
    if (_epoch != epoch || _disposed || _paused) {
      for (final profile in unlocked) {
        profile.destroy();
      }
      throw const SyncV2WorkspaceException('locked');
    }
    for (final profile in unlocked) {
      _private.remove(profile.id)?.destroy();
      _private[profile.id] = profile;
    }
  }

  Future<void> unlockPrivate(String password) => _run(() async {
    final epoch = _epoch;
    final unlocked = await _catalog.unlock(password);
    if (unlocked.isEmpty) {
      throw const SyncV2WorkspaceException('wrong_password');
    }
    _installProfiles(unlocked, epoch);
    selectedProfileId = unlocked.first.id;
    await _reloadNotes();
  });
  Future<void> unlockAdmin(String password) => _run(() async {
    final epoch = _epoch;
    final admin = await _adminStore.unlock(password);
    if (admin == null) throw const SyncV2WorkspaceException('wrong_password');
    try {
      await _registration.verifyAdminKey(
        accountId: accountId!,
        adminKey: admin,
      );
      await _rememberDeviceAdmin(admin, epoch);
      await _refreshAdminProfiles(admin, epoch);
      _admin?.destroy();
      _admin = admin;
      _adminFromSettings = false;
      await _reloadNotes();
    } catch (_) {
      admin.destroy();
      rethrow;
    }
  });
  AuthenticationThrottle get _unlockThrottle => AuthenticationThrottle(
    store: store,
    storageKey: syncV2UnlockAttemptsKey(generationId!),
    delayFor: syncV2UnlockDelay,
  );

  /// Clears the passcode retry delay. Development builds only: the caller must
  /// gate this on `AppFlavor.development`.
  Future<void> debugResetUnlockThrottle() => _run(() async {
    if (generationId == null) return;
    await _unlockThrottle.reset();
  });

  Future<void> unlockAdminBiometric() => _run(() async {
    if (!biometricEnabled) {
      throw const SyncV2WorkspaceException('biometric_unavailable');
    }
    final epoch = _epoch;
    final admin = await _authenticateBiometric(
      () => biometrics.read(generationId!),
    );
    if (admin == null) {
      throw const SyncV2WorkspaceException('biometric_unavailable');
    }
    try {
      await _registration.verifyAdminKey(
        accountId: accountId!,
        adminKey: admin,
      );
      await _rememberDeviceAdmin(admin, epoch);
      await _refreshAdminProfiles(admin, epoch);
      _admin?.destroy();
      _admin = admin;
      _adminFromSettings = false;
      await _unlockThrottle.reset();
      await _reloadNotes();
    } catch (_) {
      admin.destroy();
      rethrow;
    }
  });

  Future<void> enableAdminBiometrics() => _run(() async {
    if (_admin == null || _adminFromSettings) {
      throw const SyncV2WorkspaceException('admin_required');
    }
    final epoch = _epoch;
    final key = SecretKey(await _admin!.extractBytes());
    try {
      await _authenticateBiometric(() => biometrics.save(generationId!, key));
      if (_paused || _disposed || epoch != _epoch) {
        throw const SyncV2WorkspaceException('locked');
      }
      await store.write('sync.v2.biometric.$generationId', 'enabled');
      biometricEnabled = true;
    } finally {
      key.destroy();
    }
  });

  Future<void> recoverAdminBiometric(String code) => _run(() async {
    final epoch = _epoch;
    final admin = _adminStore.decodeRecoveryCode(code);
    try {
      await _registration.verifyAdminKey(
        accountId: accountId!,
        adminKey: admin,
      );
      await _authenticateBiometric(() => biometrics.save(generationId!, admin));
      if (_paused || _disposed || epoch != _epoch) {
        throw const SyncV2WorkspaceException('locked');
      }
      await store.write('sync.v2.biometric.$generationId', 'enabled');
      biometricEnabled = true;
      await _rememberDeviceAdmin(admin, epoch);
      await _refreshAdminProfiles(admin, epoch);
      _admin?.destroy();
      _admin = admin;
      _adminFromSettings = false;
      await _reloadNotes();
    } catch (_) {
      admin.destroy();
      rethrow;
    }
  });

  Future<void> recoverAdmin(String code, String newPassword) => _run(() async {
    final epoch = _epoch;
    final admin = _adminStore.decodeRecoveryCode(code);
    try {
      await _registration.verifyAdminKey(
        accountId: accountId!,
        adminKey: admin,
      );
      if (await _catalog.matchesPassword(newPassword)) {
        throw const SyncV2WorkspaceException('duplicate_passcode');
      }
      await _adminStore.configure(adminKey: admin, password: newPassword);
      await _rememberDeviceAdmin(admin, epoch);
      await _refreshAdminProfiles(admin, epoch);
      _admin?.destroy();
      _admin = admin;
      _adminFromSettings = false;
      await _reloadNotes();
    } catch (_) {
      admin.destroy();
      rethrow;
    }
  });
  Future<void> createProfile(String name, String password) => _run(() async {
    if (_admin == null) throw const SyncV2WorkspaceException('admin_required');
    final epoch = _epoch;
    await _checkProfilePassword(password);
    final profile = await _catalog.create(
      name: name,
      password: password,
      adminKey: _admin!,
    );
    _installProfiles([profile], epoch);
    selectedProfileId = profile.id;
    await _reloadNotes();
  });
  Future<void> changeProfilePassword(String profileId, String password) =>
      _run(() async {
        // Any administrator session (including one entered from settings after
        // device authentication) takes precedence over profile passcodes.
        if (_admin == null || !_private.containsKey(profileId)) {
          throw const SyncV2WorkspaceException('admin_required');
        }
        await _checkProfilePassword(password);
        await _catalog.changePassword(
          profile: _private[profileId]!,
          password: password,
          adminKey: _admin!,
        );
      });

  Future<void> _checkProfilePassword(String password) async {
    if (await _adminStore.matchesPassword(password)) {
      throw const SyncV2WorkspaceException('duplicate_passcode');
    }
  }

  Future<void> renameProfile(String profileId, String name) => _run(() async {
    if (_admin == null || !_private.containsKey(profileId)) {
      throw const SyncV2WorkspaceException('admin_required');
    }
    await _catalog.rename(profile: _private[profileId]!, name: name);
    await _refreshAdminProfiles(_admin!, _epoch);
    await _reloadNotes();
  });

  Future<void> deleteProfile(String profileId) => _run(() async {
    if (_admin == null || !_private.containsKey(profileId)) {
      throw const SyncV2WorkspaceException('admin_required');
    }
    final profile = _private[profileId]!;
    final epoch = _epoch;
    void checkActive() {
      if (_epoch != epoch || _disposed || _paused || _admin == null) {
        throw const SyncV2WorkspaceException('locked');
      }
    }

    await inbox.transaction(() async {
      final snapshots = await repository.readProfile(
        generationId: generationId!,
        profileId: profileId,
        syncKey: _syncKey!,
        profileKey: profile.access,
      );
      for (final entry in snapshots.entries) {
        checkActive();
        if (!entry.value.canCompareVersions || entry.value.hasConflict) {
          throw const SyncV2StaleNote();
        }
        if (entry.value.versions.every((v) => v.isDeleted)) continue;
        await repository.delete(
          generationId: generationId!,
          profileId: profileId,
          noteId: entry.key,
          changeId: _id('delete'),
          expectedHeadIds: entry.value.headIds,
          syncKey: _syncKey!,
          profileKey: profile.access,
        );
      }
      checkActive();
      await _catalog.delete(profile);
      checkActive();
    });
    _private.remove(profileId)?.destroy();
    if (selectedProfileId == profileId) selectedProfileId = _normal!.profileId;
    await _reloadNotes();
  });

  Future<void> _refreshAdminProfiles(SecretKey admin, int epoch) async {
    final unlocked = await _catalog.unlockAdmin(admin);
    try {
      final conflicts = await _catalog.conflictNames(admin);
      if (_epoch != epoch || _disposed || _paused) {
        throw const SyncV2WorkspaceException('locked');
      }
      for (final profile in _private.values) {
        profile.destroy();
      }
      _private.clear();
      _installProfiles(unlocked, epoch);
      if (!_private.containsKey(selectedProfileId)) {
        selectedProfileId = _normal?.profileId;
      }
      profileConflicts = [
        for (final entry in conflicts.entries)
          SyncV2WorkspaceProfile(entry.key, entry.value),
      ];
    } catch (_) {
      for (final profile in unlocked) {
        profile.destroy();
      }
      rethrow;
    }
  }

  Future<void> repairProfilePassword(String profileId, String password) =>
      _run(() async {
        final admin = _admin;
        if (admin == null) {
          throw const SyncV2WorkspaceException('admin_required');
        }
        final epoch = _epoch;
        await _checkProfilePassword(password);
        await _catalog.resolvePasswordConflict(
          profileId: profileId,
          password: password,
          adminKey: admin,
        );
        await _refreshAdminProfiles(admin, epoch);
        await _reloadNotes();
      });

  Future<void> _reloadNotes() async {
    if (!registered || _paused || _disposed) return;
    final epoch = _epoch;
    final access = _selected;
    final snapshots = await repository.readProfile(
      generationId: generationId!,
      profileId: access.profileId,
      syncKey: _syncKey!,
      profileKey: access,
      noteIdPrefix: 'note_',
    );
    final loaded = <SyncV2WorkspaceNote>[];
    for (final entry in snapshots.entries) {
      final snapshot = entry.value;
      // Namespace and payload type keep keys and attachment chunks out of notes.
      if (entry.key.startsWith('profile_') || entry.key.startsWith('blob_')) {
        continue;
      }
      try {
        NoteEntry? note;
        final refs = <String, SyncV2AttachmentReference>{};
        for (final version in snapshot.versions) {
          final body = version.body;
          if (body == null) {
            continue;
          }
          if (body['type'] != 'note' || body['note'] is! Map) {
            throw const FormatException('Invalid note payload');
          }
          final parsed = NoteEntry.fromJson(
            Map<String, dynamic>.from(body['note'] as Map),
          );
          if (parsed.id != entry.key || parsed.vaultId != access.profileId) {
            throw const FormatException('Invalid note identity');
          }
          note ??= parsed.copyWith(body: syncV2EditableBody(parsed));
          for (final ref in _references(body)) {
            final previous = refs[ref.id];
            if (previous != null &&
                jsonEncode(previous.toJson()) != jsonEncode(ref.toJson())) {
              throw const FormatException('Conflicting attachment reference');
            }
            refs[ref.id] = ref;
          }
        }
        note ??= NoteEntry(
          id: entry.key,
          vaultId: access.profileId,
          title: '',
          body: '',
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        );
        loaded.add(SyncV2WorkspaceNote(note, snapshot, refs.values.toList()));
      } catch (_) {
        // Quarantine only this projection. Keep the encrypted source records
        // untouched, while preventing malformed plaintext from reaching views.
        final redactedSnapshot = SyncV2NoteSnapshot(
          versions: [
            for (final version in snapshot.versions)
              SyncV2NoteVersion(
                change: version.change,
                payloadAvailable: version.payloadAvailable,
                body: null,
              ),
          ],
          pendingIds: snapshot.pendingIds,
        );
        loaded.add(
          SyncV2WorkspaceNote(
            NoteEntry(
              id: entry.key,
              vaultId: access.profileId,
              title: '',
              body: '',
              createdAt: DateTime.fromMillisecondsSinceEpoch(0),
            ),
            redactedSnapshot,
            const [],
            isCorrupt: true,
          ),
        );
      }
    }
    loaded.sort((a, b) => b.note.createdAt.compareTo(a.note.createdAt));
    final failures = await inbox.readFailures(generationId!);
    if (epoch != _epoch || _disposed) return;
    notes = List.unmodifiable(loaded);
    this.failures = failures;
    _notify();
  }

  List<SyncV2AttachmentReference> _references(Map<String, Object?> body) => [
    for (final ref in body['attachments'] as List? ?? const [])
      SyncV2AttachmentReference.fromJson(Map<String, dynamic>.from(ref as Map)),
  ];
  Future<void> saveNote({
    SyncV2WorkspaceNote? original,
    DateTime? createdAt,
    required String title,
    required String body,
    List<NoteBlock>? blocks,
    bool? isPinned,
    List<String>? tags,
    String? selectedVersionId,
    List<SyncV2PendingAttachment> addedFiles = const [],
    List<String> removedAttachmentIds = const [],
  }) {
    if (addedFiles.fold<int>(0, (sum, file) => sum + file.bytes.length) >
        syncV2MaxPendingAttachmentBytes) {
      return Future<void>.error(const SyncV2WorkspaceException('too_large'));
    }
    // The operation is queued by _run. Own a snapshot synchronously so a
    // screen lock can wipe its draft buffers without racing an active save.
    final ownedAddedFiles = [
      for (final file in addedFiles)
        SyncV2PendingAttachment(
          label: file.label,
          type: file.type,
          bytes: Uint8List.fromList(file.bytes),
          draftId: file.draftId,
        ),
    ];
    final epoch = _epoch;
    final profile = selectedProfileId;
    final operation = _run(() async {
      if (epoch != _epoch || profile != selectedProfileId) {
        throw const SyncV2WorkspaceException('locked');
      }
      void ensureActive() {
        if (epoch != _epoch || profile != selectedProfileId || _paused) {
          throw const SyncV2WorkspaceException('locked');
        }
      }

      if (utf8.encode(title).length +
              utf8.encode(body).length +
              utf8.encode(jsonEncode(tags ?? const <String>[])).length >
          2 * 1024 * 1024) {
        throw const SyncV2WorkspaceException('too_large');
      }
      final access = _selected;
      if (original != null &&
          (!original.ready || original.note.vaultId != access.profileId)) {
        throw const SyncV2StaleNote();
      }
      if (isPinned != null && original?.isConflict == true) {
        throw const SyncV2StaleNote();
      }
      if (original?.isConflict == true && selectedVersionId == null) {
        throw const SyncV2StaleNote();
      }
      NoteEntry? selectedNote;
      Map<String, Object?>? originBody = original?.versions.length == 1
          ? original!.versions.single.body
          : null;
      List<SyncV2AttachmentReference>? selectedAttachments;
      if (selectedVersionId != null) {
        final version = original!.versions.singleWhere(
          (v) => v.change.id == selectedVersionId,
        );
        if (version.body == null || version.isDeleted) {
          throw const SyncV2StaleNote();
        }
        selectedNote = NoteEntry.fromJson(
          Map<String, dynamic>.from(version.body!['note'] as Map),
        );
        selectedAttachments = _references(version.body!);
        originBody = version.body;
      }
      final id = original?.note.id ?? _id('note');
      await inbox.transaction(() async {
        final addedRefs = <SyncV2AttachmentReference>[];
        final originalReferenceList =
            selectedAttachments ??
            original?.attachments ??
            <SyncV2AttachmentReference>[];
        final originalReferenceIds = {
          for (final ref in originalReferenceList) ref.id,
        };
        if (removedAttachmentIds.toSet().length !=
                removedAttachmentIds.length ||
            removedAttachmentIds.any(
              (attachmentId) => !originalReferenceIds.contains(attachmentId),
            )) {
          throw const SyncV2WorkspaceException('rich_attachment_unlinked');
        }
        final refs = [
          for (final ref in originalReferenceList)
            if (!removedAttachmentIds.contains(ref.id)) ref,
        ];
        final draftIds = <String>{};
        for (final file in ownedAddedFiles) {
          final draftId = file.draftId;
          if (draftId != null &&
              (draftId.isEmpty ||
                  draftId.length > 128 ||
                  !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(draftId) ||
                  !draftIds.add(draftId))) {
            throw const SyncV2WorkspaceException(
              'rich_attachment_pending_invalid',
            );
          }
        }
        final addedRefsByDraftId = <String, SyncV2AttachmentReference>{};
        for (final file in ownedAddedFiles) {
          ensureActive();
          final ref = await SyncV2AttachmentService(inbox, repository).store(
            generationId: generationId!,
            syncKey: _syncKey!,
            profileAccess: access,
            bytes: file.bytes,
            label: file.label,
            type: file.type.name,
            checkActive: ensureActive,
          );
          ensureActive();
          refs.add(ref);
          addedRefs.add(ref);
          if (file.draftId case final draftId?) {
            if (originalReferenceIds.contains(ref.id) ||
                addedRefsByDraftId.values.any((entry) => entry.id == ref.id)) {
              throw const SyncV2WorkspaceException(
                'rich_attachment_pending_invalid',
              );
            }
            addedRefsByDraftId[draftId] = ref;
          }
        }
        final base =
            selectedNote ??
            original?.note ??
            NoteEntry(
              id: id,
              vaultId: access.profileId,
              title: '',
              body: '',
              createdAt: createdAt ?? DateTime.now(),
            );
        final baseBody = syncV2EditableBody(base);
        if (blocks == null && base.blocks.isNotEmpty && body != baseBody) {
          throw const SyncV2WorkspaceException('rich_blocks_required');
        }
        var savedBlocks = List<NoteBlock>.of(blocks ?? base.blocks);
        final newAttachmentBlocksById = <String, NoteBlock>{};
        final placedAddedRefIds = <String>{};
        if (blocks != null) {
          final pendingBlocksById = <String, NoteBlock>{};
          for (var index = 0; index < savedBlocks.length; index++) {
            final block = savedBlocks[index];
            final path = block.attachment?.filePath;
            if (path == null || !path.startsWith('v2pending:')) continue;
            final draftId = path.substring('v2pending:'.length);
            final file = ownedAddedFiles
                .where((file) => file.draftId == draftId)
                .firstOrNull;
            final ref = addedRefsByDraftId[draftId];
            final expectedDraftAttachment = file == null
                ? null
                : NoteAttachment(
                    type: file.type,
                    label: file.label,
                    filePath: 'v2pending:$draftId',
                  );
            if (draftId.isEmpty ||
                file == null ||
                ref == null ||
                expectedDraftAttachment != block.attachment ||
                block.type.name != file.type.name ||
                pendingBlocksById.containsKey(draftId)) {
              throw const SyncV2WorkspaceException(
                'rich_attachment_pending_invalid',
              );
            }
            final resolved = NoteBlock(
              type: block.type,
              attachment: NoteAttachment(
                type: file.type,
                label: file.label,
                filePath: 'v2attachment:${ref.id}',
                syncAttachmentContentHash: ref.sha256,
              ),
            );
            savedBlocks[index] = resolved;
            pendingBlocksById[draftId] = resolved;
            newAttachmentBlocksById[ref.id] = resolved;
            placedAddedRefIds.add(ref.id);
          }
          if (draftIds.any(
            (draftId) => !pendingBlocksById.containsKey(draftId),
          )) {
            throw const SyncV2WorkspaceException(
              'rich_attachment_pending_invalid',
            );
          }
        }
        if (blocks != null &&
            syncV2EditableBody(base.copyWith(blocks: blocks)) != body) {
          throw const SyncV2WorkspaceException('rich_blocks_body_mismatch');
        }
        if (blocks != null) {
          final originalReferencesById = {
            for (final ref in originalReferenceList) ref.id: ref,
          };
          final originalLinkedCountsById = <String, Map<NoteBlock, int>>{};
          final originalUnlinkedAttachmentCounts = <NoteBlock, int>{};
          for (final block in base.blocks) {
            if (block.type == NoteBlockType.paragraph) continue;
            final attachment = block.attachment;
            final path = attachment?.filePath;
            if (attachment == null || block.type.name != attachment.type.name) {
              throw const SyncV2WorkspaceException(
                'rich_blocks_structure_changed',
              );
            }
            if (path?.startsWith('v2attachment:') ?? false) {
              final id = path!.substring('v2attachment:'.length);
              if (!originalReferencesById.containsKey(id)) {
                throw const SyncV2WorkspaceException(
                  'rich_blocks_structure_changed',
                );
              }
              originalLinkedCountsById
                  .putIfAbsent(id, () => <NoteBlock, int>{})
                  .update(block, (count) => count + 1, ifAbsent: () => 1);
            } else {
              originalUnlinkedAttachmentCounts.update(
                block,
                (count) => count + 1,
                ifAbsent: () => 1,
              );
            }
          }

          final editedLinkedCountsById = <String, Map<NoteBlock, int>>{};
          final editedUnlinkedAttachmentCounts = <NoteBlock, int>{};
          var invalidBlock = false;
          for (final block in savedBlocks) {
            if (block.type == NoteBlockType.paragraph) {
              if (block.attachment != null) invalidBlock = true;
              continue;
            }
            final attachment = block.attachment;
            final path = attachment?.filePath;
            if (attachment == null || block.type.name != attachment.type.name) {
              invalidBlock = true;
              continue;
            }
            if (path?.startsWith('v2attachment:') ?? false) {
              final id = path!.substring('v2attachment:'.length);
              final reference =
                  originalReferencesById[id] ??
                  addedRefs.where((ref) => ref.id == id).firstOrNull;
              final originalCount = originalLinkedCountsById[id]?[block] ?? 0;
              final newBlock = newAttachmentBlocksById[id];
              final count = editedLinkedCountsById
                  .putIfAbsent(id, () => <NoteBlock, int>{})
                  .update(block, (count) => count + 1, ifAbsent: () => 1);
              final isNewPendingBlock = originalCount == 0;
              if (reference == null ||
                  block.type.name != reference.type ||
                  attachment.type.name != reference.type ||
                  (isNewPendingBlock
                      ? newBlock == null || block != newBlock || count > 1
                      : count > originalCount)) {
                invalidBlock = true;
              }
            } else {
              final count = editedUnlinkedAttachmentCounts.update(
                block,
                (count) => count + 1,
                ifAbsent: () => 1,
              );
              if (count > (originalUnlinkedAttachmentCounts[block] ?? 0)) {
                invalidBlock = true;
              }
            }
          }
          bool sameBlockCounts(
            Map<NoteBlock, int> expected,
            Map<NoteBlock, int> actual,
          ) =>
              expected.length == actual.length &&
              expected.entries.every(
                (entry) => actual[entry.key] == entry.value,
              );
          final linkedAttachmentsMatch = originalLinkedCountsById.entries.every(
            (entry) {
              final edited = editedLinkedCountsById[entry.key] ?? const {};
              if (removedAttachmentIds.contains(entry.key)) {
                return edited.isEmpty || sameBlockCounts(entry.value, edited);
              }
              return sameBlockCounts(entry.value, edited);
            },
          );
          final unlinkedAttachmentsMatch = originalUnlinkedAttachmentCounts
              .entries
              .every(
                (entry) =>
                    editedUnlinkedAttachmentCounts[entry.key] == entry.value,
              );
          if (invalidBlock ||
              !linkedAttachmentsMatch ||
              !unlinkedAttachmentsMatch) {
            throw const SyncV2WorkspaceException(
              'rich_blocks_structure_changed',
            );
          }
        }
        if (savedBlocks.isEmpty &&
            body.isNotEmpty &&
            base.editorMode == NoteEditorMode.rich) {
          savedBlocks.add(NoteBlock(type: NoteBlockType.paragraph, text: body));
        }
        if (removedAttachmentIds.isNotEmpty) {
          savedBlocks.removeWhere((block) {
            final path = block.attachment?.filePath;
            return path != null &&
                removedAttachmentIds.contains(
                  path.substring('v2attachment:'.length),
                );
          });
        }
        for (final ref in addedRefs) {
          if (placedAddedRefIds.contains(ref.id)) continue;
          if (blocks == null && base.editorMode == NoteEditorMode.quick) {
            continue;
          }
          final attachment = NoteAttachment(
            type: AttachmentType.values.byName(ref.type),
            label: ref.label,
            filePath: 'v2attachment:${ref.id}',
            syncAttachmentContentHash: ref.sha256,
          );
          savedBlocks.add(
            NoteBlock(
              type: NoteBlockType.values.byName(ref.type),
              attachment: attachment,
            ),
          );
        }
        final refsById = {for (final ref in refs) ref.id: ref};
        for (final block in savedBlocks) {
          final path = block.attachment?.filePath;
          if (path != null && path.startsWith('v2pending:')) {
            throw const SyncV2WorkspaceException(
              'rich_attachment_pending_invalid',
            );
          }
          if (path != null &&
              path.startsWith('v2attachment:') &&
              !refsById.containsKey(path.substring('v2attachment:'.length))) {
            throw const SyncV2WorkspaceException('rich_attachment_unlinked');
          }
        }
        // Preserve legacy unlinked attachments and existing per-attachment
        // metadata when a different attachment is added or removed.
        final representedIds = <String>{};
        final remainingAttachments = <NoteAttachment>[];
        for (final attachment in base.attachments) {
          final path = attachment.filePath;
          if (path == null || !path.startsWith('v2attachment:')) {
            remainingAttachments.add(attachment);
            continue;
          }
          final id = path.substring('v2attachment:'.length);
          final ref = refsById[id];
          if (ref == null) continue;
          representedIds.add(id);
          remainingAttachments.add(
            attachment.copyWith(syncAttachmentContentHash: ref.sha256),
          );
        }
        for (final ref in refs) {
          if (representedIds.add(ref.id)) {
            remainingAttachments.add(
              NoteAttachment(
                type: AttachmentType.values.byName(ref.type),
                label: ref.label,
                filePath: 'v2attachment:${ref.id}',
                syncAttachmentContentHash: ref.sha256,
              ),
            );
          }
        }
        final note = base.copyWith(
          title: title,
          body: body,
          isPinned: isPinned ?? base.isPinned,
          tags: tags == null ? base.tags : dedupeNoteTags(tags),
          updatedAt: DateTime.now(),
          deletedAt: null,
          attachments: ownedAddedFiles.isEmpty && removedAttachmentIds.isEmpty
              ? base.attachments
              : remainingAttachments,
          blocks: savedBlocks,
        );
        ensureActive();
        await repository.save(
          generationId: generationId!,
          profileId: access.profileId,
          noteId: id,
          changeId: _id('change'),
          expectedHeadIds: original?.headIds ?? {},
          body: {
            'type': 'note',
            'note': note.toJson(),
            'attachments': refs.map((r) => r.toJson()).toList(),
            if (originBody?['legacyImport'] is Map)
              'legacyImport': originBody!['legacyImport'],
          },
          syncKey: _syncKey!,
          profileKey: access,
        );
        ensureActive();
      });
      await _reloadNotes();
    });
    return operation.whenComplete(() {
      for (final file in ownedAddedFiles) {
        file.bytes.fillRange(0, file.bytes.length, 0);
      }
    });
  }

  /// Atomically updates one tag in the selected unlocked profile.
  /// Incomplete or conflicting snapshots must be resolved first so that a
  /// bulk edit cannot silently discard an unseen version.
  Future<void> updateTag(String source, {String? replacement}) {
    final epoch = _epoch;
    final profile = selectedProfileId;
    return _run(() async {
      if (epoch != _epoch || profile == null || profile != selectedProfileId) {
        throw const SyncV2WorkspaceException('locked');
      }
      final oldKey = canonicalizeNoteTag(source);
      final newTag = replacement == null ? null : normalizeNoteTag(replacement);
      if (oldKey.isEmpty || (replacement != null && newTag!.isEmpty)) {
        throw const SyncV2WorkspaceException('invalid_tag');
      }
      final access = _selected;
      final selectedNotes = notes
          .where((entry) => entry.note.vaultId == profile)
          .toList();
      if (selectedNotes.any((entry) => entry.isCorrupt)) {
        throw const SyncV2WorkspaceException('tag_corrupt');
      }
      if (selectedNotes.any((entry) => !entry.ready || entry.isConflict)) {
        throw const SyncV2WorkspaceException('tag_conflict');
      }
      final targets = selectedNotes
          .where(
            (entry) =>
                !entry.isDeleted &&
                entry.note.deletedAt == null &&
                entry.note.normalizedTags.any(
                  (tag) => canonicalizeNoteTag(tag) == oldKey,
                ),
          )
          .toList();
      await inbox.transaction(() async {
        for (final entry in targets) {
          if (epoch != _epoch || profile != selectedProfileId) {
            throw const SyncV2WorkspaceException('locked');
          }
          final version = entry.versions.single;
          final body = version.body;
          if (body == null || version.isDeleted) throw const SyncV2StaleNote();
          final updatedTags = dedupeNoteTags([
            for (final tag in entry.note.normalizedTags)
              if (canonicalizeNoteTag(tag) != oldKey) tag else ?newTag,
          ]);
          final original = NoteEntry.fromJson(
            Map<String, dynamic>.from(body['note'] as Map),
          );
          if (original.id != entry.note.id || original.vaultId != profile) {
            throw const SyncV2StaleNote();
          }
          final updated = original.copyWith(
            tags: updatedTags,
            updatedAt: DateTime.now(),
          );
          await repository.save(
            generationId: generationId!,
            profileId: profile,
            noteId: entry.note.id,
            changeId: _id('change'),
            expectedHeadIds: entry.headIds,
            body: {...body, 'note': updated.toJson()},
            syncKey: _syncKey!,
            profileKey: access,
          );
        }
        if (epoch != _epoch || profile != selectedProfileId) {
          throw const SyncV2WorkspaceException('locked');
        }
      });
      await _reloadNotes();
    });
  }

  Future<void> restoreDeletedNote(SyncV2WorkspaceNote note) {
    final epoch = _epoch;
    final profile = selectedProfileId;
    return _run(() async {
      if (profile == null ||
          profile != selectedProfileId ||
          epoch != _epoch ||
          note.note.vaultId != profile ||
          !note.ready ||
          note.isConflict ||
          (!note.isDeleted && note.note.deletedAt == null)) {
        throw const SyncV2StaleNote();
      }
      final access = _selected;
      await inbox.transaction(() async {
        final body = note.isDeleted
            ? await repository.readDeletedPredecessor(
                generationId: generationId!,
                profileId: profile,
                noteId: note.note.id,
                expectedHeadIds: note.headIds,
                syncKey: _syncKey!,
                profileKey: access,
              )
            : note.versions.single.body;
        if (body == null) throw const SyncV2StaleNote();
        if (epoch != _epoch ||
            profile != selectedProfileId ||
            body['type'] != 'note' ||
            body['note'] is! Map) {
          throw const SyncV2StaleNote();
        }
        final original = NoteEntry.fromJson(
          Map<String, dynamic>.from(body['note'] as Map),
        );
        if (original.id != note.note.id || original.vaultId != profile) {
          throw const SyncV2StaleNote();
        }
        await repository.save(
          generationId: generationId!,
          profileId: profile,
          noteId: note.note.id,
          changeId: _id('change'),
          expectedHeadIds: note.headIds,
          body: {
            ...body,
            'note': original
                .copyWith(deletedAt: null, updatedAt: DateTime.now())
                .toJson(),
          },
          syncKey: _syncKey!,
          profileKey: access,
        );
        if (epoch != _epoch || profile != selectedProfileId) {
          throw const SyncV2StaleNote();
        }
      });
      await _reloadNotes();
    });
  }

  Future<void> deleteNote(SyncV2WorkspaceNote note) => _run(() async {
    if (note.note.vaultId != _selected.profileId) {
      throw const SyncV2WorkspaceException('locked');
    }
    if (!note.ready) throw const SyncV2StaleNote();
    await repository.delete(
      generationId: generationId!,
      profileId: _selected.profileId,
      noteId: note.note.id,
      changeId: _id('change'),
      expectedHeadIds: note.headIds,
      syncKey: _syncKey!,
      profileKey: _selected,
    );
    await _reloadNotes();
  });

  /// Archives or unarchives one complete note in the currently unlocked
  /// profile. The original encrypted payload is copied so attachments, tags,
  /// and rich blocks remain intact. Partial and conflicting notes are refused.
  Future<void> setNoteArchived(
    SyncV2WorkspaceNote note, {
    required bool archived,
  }) {
    final epoch = _epoch;
    final profile = selectedProfileId;
    return _run(() async {
      if (profile == null ||
          profile != selectedProfileId ||
          epoch != _epoch ||
          note.note.vaultId != profile ||
          !note.ready ||
          note.isConflict ||
          note.isDeleted ||
          note.note.deletedAt != null ||
          note.versions.length != 1) {
        throw const SyncV2StaleNote();
      }
      final version = note.versions.single;
      final body = version.body;
      if (body == null ||
          version.isDeleted ||
          body['type'] != 'note' ||
          body['note'] is! Map) {
        throw const SyncV2StaleNote();
      }
      final original = NoteEntry.fromJson(
        Map<String, dynamic>.from(body['note'] as Map),
      );
      if (original.id != note.note.id || original.vaultId != profile) {
        throw const SyncV2StaleNote();
      }
      await inbox.transaction(() async {
        if (epoch != _epoch || profile != selectedProfileId) {
          throw const SyncV2StaleNote();
        }
        await repository.save(
          generationId: generationId!,
          profileId: profile,
          noteId: note.note.id,
          changeId: _id('change'),
          expectedHeadIds: note.headIds,
          body: {
            ...body,
            'note': original
                .copyWith(
                  archivedAt: archived ? DateTime.now() : null,
                  updatedAt: DateTime.now(),
                )
                .toJson(),
          },
          syncKey: _syncKey!,
          profileKey: _selected,
        );
        if (epoch != _epoch || profile != selectedProfileId) {
          throw const SyncV2StaleNote();
        }
      });
      await _reloadNotes();
    });
  }

  Future<void> syncNow() => _run(_sync);
  Future<void> _sync() async {
    if (!registered) return;
    final epoch = _epoch;
    // Verify before doing any work; cached offline access never grants sync.
    if (await registrationTransport.readCurrentAccountId() != accountId) {
      if (_epoch != epoch || _paused || _disposed || !registered) return;
      lockPrivate();
      throw const SyncV2WorkspaceException('account_changed');
    }
    if (_epoch != epoch || _paused || _disposed || !registered) return;
    for (var page = 0; page < 20; page++) {
      final progress = await syncOperation();
      if (_epoch != epoch || _paused || _disposed || !registered) return;
      if (progress.errors.isNotEmpty) {
        throw const SyncV2WorkspaceException('sync_failed');
      }
      if (!progress.hasMoreHeaders && progress.publishedChanges < 50) break;
    }
    if (_admin != null) {
      await _refreshAdminProfiles(_admin!, epoch);
    } else if (_private.isNotEmpty) {
      final names = await _catalog.unlockedNames(_private.values.toList());
      if (_epoch != epoch || _disposed || _paused) return;
      for (final id in _private.keys.toList()) {
        final profile = _private[id]!;
        if (!names.containsKey(id)) {
          _private.remove(id)?.destroy();
        } else {
          _private[id] = SyncV2UnlockedProfile(
            name: names[id]!,
            access: profile.access,
          );
        }
      }
      if (selectedProfileId != _normal?.profileId &&
          !_private.containsKey(selectedProfileId)) {
        selectedProfileId = _normal?.profileId;
      }
    }
    await _reloadNotes();
  }

  Future<void> retryFailure(String id, String phase) => _run(() async {
    if (phase == 'publication') {
      await inbox.retryPublication(generationId: generationId!, recordId: id);
    } else if (phase == 'payload') {
      await inbox.retryPayload(generationId: generationId!, recordId: id);
    } else {
      await inbox.retryHeader(generationId: generationId!, recordId: id);
    }
    await _sync();
  });
  Future<SyncV2ArchiveInspection> inspectArchive(
    Uint8List bytes, {
    String? password,
  }) => _run(
    () async => SyncV2ArchiveService(
      inbox,
      repository,
    ).inspect(bytes, password: password),
  );

  /// Explicit administrator authority replaces known versions with the ZIP.
  /// Destination creation, notes, attachments and outbox commit together.
  Future<void> adminImportArchive({
    required Uint8List bytes,
    String? password,
    SyncV2ArchiveInspection? inspection,
  }) => _run(() async {
    if (_admin == null || !registered) {
      throw const SyncV2WorkspaceException('admin_required');
    }
    final epoch = _epoch;
    final admin = SecretKey(List<int>.of(await _admin!.extractBytes()));
    final opened = <SyncV2UnlockedProfile>[];
    var installed = false;
    void checkActive() {
      if (_disposed ||
          _paused ||
          epoch != _epoch ||
          (_adminFromSettings && !settingsAdminActive)) {
        throw const SyncV2WorkspaceException('locked');
      }
    }

    try {
      checkActive();
      // Fetch known parents/catalog updates where possible. Offline restore
      // remains local, while incomplete catalog/history is reported distinctly.
      try {
        await _sync();
      } on SyncV2CloudDataDeleted {
        rethrow;
      } on SyncV2WorkspaceException catch (failure) {
        if (failure.code == 'account_changed' || failure.code == 'locked') {
          rethrow;
        }
      } catch (_) {
        // Final authenticated header/catalog checks still run in the transaction.
      }
      checkActive();
      final writerId = _id('archive_writer');
      final service = SyncV2ArchiveService(inbox, repository);
      final plan =
          inspection ?? await service.inspect(bytes, password: password);
      checkActive();
      final sources =
          plan.noteCountsByProfile.keys
              .where((source) => source != 'everyday')
              .toList()
            ..sort();
      await inbox.transaction(() async {
        final mapped = <String, SyncV2UnlockedProfileKey>{'everyday': _normal!};
        for (var i = 0; i < sources.length; i++) {
          checkActive();
          final profile = await _catalog.ensureImportProfile(
            sourceProfileId: sources[i],
            name: 'プライベート ${i + 1}',
            adminKey: admin,
          );
          opened.add(profile);
          mapped[sources[i]] = profile.access;
          checkActive();
        }
        await service.importArchive(
          bytes: bytes,
          password: password,
          generationId: generationId!,
          syncKey: _syncKey!,
          destinations: mapped,
          acceptUnlinkedAttachments: true,
          overwriteExisting: true,
          writerId: writerId,
          checkActive: checkActive,
        );
        checkActive();
      });
      checkActive();
      _installProfiles(opened, epoch);
      installed = true;
      await _refreshAdminProfiles(admin, epoch);
      selectedProfileId = _normal!.profileId;
      await _reloadNotes();
    } on SyncV2StaleNote {
      throw const SyncV2WorkspaceException('sync_required');
    } finally {
      admin.destroy();
      if (!installed) {
        for (final profile in opened) {
          profile.destroy();
        }
      }
    }
  });

  Future<void> importArchive({
    required Uint8List bytes,
    String? password,
    required Map<String, String> destinations,
    required bool acceptUnlinkedAttachments,
  }) => _run(() async {
    final mapped = <String, SyncV2UnlockedProfileKey>{'everyday': _normal!};
    for (final entry in destinations.entries) {
      final access = entry.value == _normal!.profileId
          ? _normal!
          : _private[entry.value]?.access;
      if (access == null) throw const SyncV2WorkspaceException('locked');
      mapped[entry.key] = access;
    }
    await SyncV2ArchiveService(inbox, repository).importArchive(
      bytes: bytes,
      password: password,
      generationId: generationId!,
      syncKey: _syncKey!,
      destinations: mapped,
      acceptUnlinkedAttachments: acceptUnlinkedAttachments,
    );
    await _reloadNotes();
  });
  Future<Uint8List> exportArchive() => _run(
    () => _protectBytes(
      () => SyncV2ArchiveService(inbox, repository).exportArchive(
        generationId: generationId!,
        syncKey: _syncKey!,
        profiles: [_selected],
      ),
    ),
  );
  Future<Uint8List> readAttachment(SyncV2AttachmentReference reference) => _run(
    () => _protectBytes(
      () => SyncV2AttachmentService(inbox, repository).read(
        reference: reference,
        generationId: generationId!,
        syncKey: _syncKey!,
        profileAccess: _selected,
      ),
    ),
  );

  /// Reads attachment bytes for an in-app preview without changing workspace
  /// operation state (in particular, without toggling [busy] or notifying).
  /// The read is serialized with other workspace operations and discarded if
  /// the unlocked session changes while it is queued or running.
  Future<Uint8List> readAttachmentPreview(
    SyncV2AttachmentReference reference, {
    bool Function()? isActive,
  }) {
    final result = Completer<Uint8List>();
    final epoch = _epoch;
    final profileId = selectedProfileId;
    final requestedGeneration = generationId;

    bool active() =>
        supported &&
        registered &&
        !_disposed &&
        !_paused &&
        epoch == _epoch &&
        profileId != null &&
        profileId == selectedProfileId &&
        requestedGeneration != null &&
        requestedGeneration == generationId &&
        _syncKey != null &&
        (isActive == null || isActive());

    void checkActive() {
      if (!active()) throw const SyncV2WorkspaceException('locked');
    }

    Future<void> read() async {
      Uint8List? bytes;
      try {
        checkActive();
        final access = _selected;
        if (access.profileId != profileId) {
          throw const SyncV2WorkspaceException('locked');
        }
        bytes = await SyncV2AttachmentService(inbox, repository).read(
          reference: reference,
          generationId: requestedGeneration!,
          syncKey: _syncKey!,
          profileAccess: access,
          checkActive: checkActive,
        );
        checkActive();
        result.complete(bytes);
      } catch (failure, stackTrace) {
        if (bytes != null) bytes.fillRange(0, bytes.length, 0);
        result.completeError(failure, stackTrace);
      }
    }

    // Keep _tail successful even if a prior operation unexpectedly failed.
    _tail = _tail.then((_) => read(), onError: (_) => read());
    return result.future;
  }

  Future<Uint8List> _protectBytes(Future<Uint8List> Function() read) async {
    final epoch = _epoch;
    final bytes = await read();
    if (epoch != _epoch || _paused || _disposed) {
      bytes.fillRange(0, bytes.length, 0);
      throw const SyncV2WorkspaceException('locked');
    }
    return bytes;
  }

  Future<({String syncCode, String? adminCode})> showRecoveryCodes() =>
      _run(() async {
        final epoch = _epoch;
        final sync = await _registration.exportRecoveryCode(
          accountId: accountId!,
        );
        final admin = _admin == null || _adminFromSettings
            ? null
            : await _adminStore.encodeRecoveryCode(_admin!);
        if (epoch != _epoch) throw const SyncV2WorkspaceException('locked');
        return (syncCode: sync, adminCode: admin);
      });
  Future<void> leaveV2() => _run(() async {
    background();
    await deactivate();
  });
  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    background();
    unawaited(
      _tail.then((_) {
        _discardPrepared();
        _normal?.destroy();
        _syncKey?.destroy();
        return inbox.close();
      }),
    );
    super.dispose();
  }
}
