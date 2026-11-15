import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

import '../../home/domain/note_entry.dart';
import '../../home/presentation/home_providers.dart';
import '../../security/data/authentication_throttle.dart';
import '../../security/data/encryption_service.dart';
import '../../security/data/secure_key_value_store.dart';
import '../../security/data/sync_v2_admin_store.dart';
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
import '../data/sync_v2_payload_codec.dart';
import '../data/sync_v2_profile_catalog.dart';

export '../data/sync_v2_archive_service.dart' show SyncV2ArchiveInspection;
export '../data/sync_v2_attachment_service.dart' show SyncV2AttachmentReference;

const syncV2EnabledPreference = 'settings.sync_v2.enabled';

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
      if (prefs.getBool(syncV2EnabledPreference) != true &&
          !await prefs.setString(
            'settings.sync_v2.previous_provider',
            ref.read(syncProviderControllerProvider).name,
          )) {
        throw StateError('Could not preserve legacy sync selection');
      }
      await ref
          .read(syncTransferControllerProvider.notifier)
          .suspendLegacyForV2();
      if (!await prefs.setBool(syncV2EnabledPreference, true)) {
        throw StateError('Could not select v2');
      }
    },
    deactivate: () async {
      final prefs = await SharedPreferences.getInstance();
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
    supported: !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS,
  );
  ref.onDispose(workspace.dispose);
  return workspace;
});

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
  });
  final String label;
  final AttachmentType type;
  final Uint8List bytes;
}

class SyncV2WorkspaceNote {
  SyncV2WorkspaceNote(this.note, this.snapshot, this.attachments);
  final NoteEntry note;
  final SyncV2NoteSnapshot snapshot;
  final List<SyncV2AttachmentReference> attachments;
  Set<String> get headIds => snapshot.headIds;
  List<SyncV2NoteVersion> get versions => snapshot.versions;
  bool get isConflict => snapshot.hasConflict;
  bool get isDeleted =>
      versions.isNotEmpty && versions.every((v) => v.isDeleted);
  bool get ready => snapshot.canCompareVersions;
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
    bool automaticSync = true,
  }) : biometrics = biometricStore ?? MethodChannelSyncV2BiometricKeyStore() {
    if (automaticSync) {
      _timer = Timer.periodic(const Duration(seconds: 60), (_) {
        if (registered && !_paused && !busy) {
          unawaited(syncNow().catchError((Object _) {}));
        }
      });
    }
  }
  final SyncV2BiometricKeyStore biometrics;
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
  bool get hasPreparedSetup => _prepared != null;
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
    _admin = _setupAdmin;
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
      await _refreshAdminProfiles(admin, epoch);
      _admin?.destroy();
      _admin = admin;
      await _reloadNotes();
    } catch (_) {
      admin.destroy();
      rethrow;
    }
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
      await _refreshAdminProfiles(admin, epoch);
      _admin?.destroy();
      _admin = admin;
      await _reloadNotes();
    } catch (_) {
      admin.destroy();
      rethrow;
    }
  });

  Future<void> enableAdminBiometrics() => _run(() async {
    if (_admin == null) throw const SyncV2WorkspaceException('admin_required');
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
      await _refreshAdminProfiles(admin, epoch);
      _admin?.destroy();
      _admin = admin;
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
      await _adminStore.configure(adminKey: admin, password: newPassword);
      await _refreshAdminProfiles(admin, epoch);
      _admin?.destroy();
      _admin = admin;
      await _reloadNotes();
    } catch (_) {
      admin.destroy();
      rethrow;
    }
  });
  Future<void> createProfile(String name, String password) => _run(() async {
    if (_admin == null) throw const SyncV2WorkspaceException('admin_required');
    final epoch = _epoch;
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
        if (_admin == null || !_private.containsKey(profileId)) {
          throw const SyncV2WorkspaceException('admin_required');
        }
        await _catalog.changePassword(
          profile: _private[profileId]!,
          password: password,
          adminKey: _admin!,
        );
      });

  Future<void> _refreshAdminProfiles(SecretKey admin, int epoch) async {
    final unlocked = await _catalog.unlockAdmin(admin);
    try {
      final conflicts = await _catalog.conflictNames(admin);
      _installProfiles(unlocked, epoch);
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

  Future<void> repairProfilePassword(String profileId, String password) => _run(
    () async {
      final admin = _admin;
      if (admin == null) throw const SyncV2WorkspaceException('admin_required');
      final epoch = _epoch;
      await _catalog.resolvePasswordConflict(
        profileId: profileId,
        password: password,
        adminKey: admin,
      );
      await _refreshAdminProfiles(admin, epoch);
      await _reloadNotes();
    },
  );

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
      NoteEntry? note;
      final refs = <String, SyncV2AttachmentReference>{};
      for (final version in snapshot.versions) {
        final body = version.body;
        if (body == null || body['type'] != 'note' || body['note'] is! Map) {
          continue;
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
    required String title,
    required String body,
    String? selectedVersionId,
    List<SyncV2PendingAttachment> addedFiles = const [],
    List<String> removedAttachmentIds = const [],
  }) {
    final epoch = _epoch;
    final profile = selectedProfileId;
    return _run(() async {
      if (epoch != _epoch || profile != selectedProfileId) {
        throw const SyncV2WorkspaceException('locked');
      }
      if (utf8.encode(title).length + utf8.encode(body).length >
          2 * 1024 * 1024) {
        throw const SyncV2WorkspaceException('too_large');
      }
      final access = _selected;
      if (original != null &&
          (!original.ready || original.note.vaultId != access.profileId)) {
        throw const SyncV2StaleNote();
      }
      if (original?.isConflict == true && selectedVersionId == null) {
        throw const SyncV2StaleNote();
      }
      NoteEntry? selectedNote;
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
      }
      final id = original?.note.id ?? _id('note');
      await inbox.transaction(() async {
        final refs = [
          for (final ref
              in selectedAttachments ??
                  original?.attachments ??
                  <SyncV2AttachmentReference>[])
            if (!removedAttachmentIds.contains(ref.id)) ref,
        ];
        for (final file in addedFiles) {
          refs.add(
            await SyncV2AttachmentService(inbox, repository).store(
              generationId: generationId!,
              syncKey: _syncKey!,
              profileAccess: access,
              bytes: file.bytes,
              label: file.label,
              type: file.type.name,
            ),
          );
        }
        final base =
            selectedNote ??
            original?.note ??
            NoteEntry(
              id: id,
              vaultId: access.profileId,
              title: '',
              body: '',
              createdAt: DateTime.now(),
            );
        final remainingAttachments = [
          for (final ref in refs)
            NoteAttachment(
              type: AttachmentType.values.byName(ref.type),
              label: ref.label,
              filePath: 'v2attachment:${ref.id}',
            ),
        ];
        final note = base.copyWith(
          title: title,
          body: body,
          updatedAt: DateTime.now(),
          deletedAt: null,
          attachments: remainingAttachments,
          blocks: base.blocks.isEmpty
              ? []
              : [
                  NoteBlock(type: NoteBlockType.paragraph, text: body),
                  for (final attachment in remainingAttachments)
                    NoteBlock(
                      type: NoteBlockType.values.byName(attachment.type.name),
                      attachment: attachment,
                    ),
                ],
        );
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
          },
          syncKey: _syncKey!,
          profileKey: access,
        );
      });
      await _reloadNotes();
    });
  }

  Future<void> deleteNote(SyncV2WorkspaceNote note) => _run(() async {
    if (note.note.vaultId != _selected.profileId) {
      throw const SyncV2WorkspaceException('locked');
    }
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

  Future<void> syncNow() => _run(_sync);
  Future<void> _sync() async {
    if (!registered) return;
    // Verify before doing any work; cached offline access never grants sync.
    if (await registrationTransport.readCurrentAccountId() != accountId) {
      lockPrivate();
      throw const SyncV2WorkspaceException('account_changed');
    }
    for (var page = 0; page < 20; page++) {
      final progress = await syncOperation();
      if (progress.errors.isNotEmpty) {
        throw const SyncV2WorkspaceException('sync_failed');
      }
      if (!progress.hasMoreHeaders && progress.publishedChanges < 50) break;
    }
    final epoch = _epoch;
    if (_admin != null) {
      await _refreshAdminProfiles(_admin!, epoch);
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
        final admin = _admin == null
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
