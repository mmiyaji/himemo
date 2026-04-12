import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path/path.dart' as path;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../data/home_repository.dart';
import '../domain/note_entry.dart';
import '../domain/vault_models.dart';
import '../../security/data/device_identity_store.dart';
import '../../security/data/encrypted_note_store.dart';
import '../../security/data/encrypted_note_database.dart';
import '../../security/data/encrypted_attachment_store.dart';
import '../../security/data/encryption_service.dart';
import '../../security/data/master_key_service.dart';
import '../../security/data/private_vault_secret_store.dart';
import '../../security/data/secure_key_value_store.dart';
import '../../sync/data/google_drive_sync_transport.dart';
import '../../sync/data/sync_conflict_policy.dart';
import '../../sync/data/secure_sync_bundle_store.dart';
import '../../sync/data/sync_bundle_key_service.dart';
import '../../sync/data/sync_bundle_state_store.dart';
import '../../sync/data/sync_engine.dart';

part 'home_providers.g.dart';

enum AppColorTheme { blue, green, orange }

enum SyncProvider { off, iCloud, googleDrive }

enum AppLaunchSurface { onboarding, ready }

enum AppLockRelockDelay { immediate, seconds30, minutes2, minutes10 }

enum DeviceAuthAvailability { unknown, available, unavailable }

enum SyncAuthStage { idle, busy, authenticated, unsupported, error }

enum SyncTransferStage { idle, busy, success, error }

enum MediaImportAction {
  takePhoto,
  pickPhoto,
  recordVideo,
  pickVideo,
  pickAudio,
}

class MediaImportResult {
  const MediaImportResult._({
    this.attachment,
    this.errorMessage,
    required this.wasCancelled,
  });

  const MediaImportResult.success(NoteAttachment attachment)
    : this._(attachment: attachment, wasCancelled: false);

  const MediaImportResult.cancelled()
    : this._(wasCancelled: true, attachment: null, errorMessage: null);

  const MediaImportResult.failure(String errorMessage)
    : this._(
        attachment: null,
        errorMessage: errorMessage,
        wasCancelled: false,
      );

  final NoteAttachment? attachment;
  final String? errorMessage;
  final bool wasCancelled;
}

class DeviceAuthState {
  const DeviceAuthState({
    required this.availability,
    required this.methods,
    this.lastError,
  });

  const DeviceAuthState.unknown()
    : availability = DeviceAuthAvailability.unknown,
      methods = const [],
      lastError = null;

  final DeviceAuthAvailability availability;
  final List<String> methods;
  final String? lastError;

  bool get isAvailable => availability == DeviceAuthAvailability.available;

  String get summary {
    if (isAvailable && methods.isNotEmpty) {
      return methods.join(', ');
    }
    if (isAvailable) {
      return 'Device credential available';
    }
    if (lastError != null && lastError!.isNotEmpty) {
      return lastError!;
    }
    return 'Biometric or device credential is not available on this device.';
  }
}

class SyncAuthState {
  const SyncAuthState({
    required this.provider,
    required this.stage,
    this.userId,
    this.displayName,
    this.email,
    this.message,
  });

  const SyncAuthState.idle(this.provider)
    : stage = SyncAuthStage.idle,
      userId = null,
      displayName = null,
      email = null,
      message = null;

  final SyncProvider provider;
  final SyncAuthStage stage;
  final String? userId;
  final String? displayName;
  final String? email;
  final String? message;

  bool get isAuthenticated => stage == SyncAuthStage.authenticated;

  SyncAuthState copyWith({
    SyncProvider? provider,
    SyncAuthStage? stage,
    String? userId,
    String? displayName,
    String? email,
    String? message,
    bool clearMessage = false,
  }) {
    return SyncAuthState(
      provider: provider ?? this.provider,
      stage: stage ?? this.stage,
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      message: clearMessage ? null : (message ?? this.message),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'provider': provider.name,
      'stage': stage.name,
      'userId': userId,
      'displayName': displayName,
      'email': email,
      'message': message,
    };
  }

  static SyncAuthState fromJson(Map<String, dynamic> json) {
    final provider = SyncProvider.values.firstWhere(
      (value) => value.name == json['provider'],
      orElse: () => SyncProvider.off,
    );
    final stage = SyncAuthStage.values.firstWhere(
      (value) => value.name == json['stage'],
      orElse: () => SyncAuthStage.idle,
    );
    return SyncAuthState(
      provider: provider,
      stage: stage,
      userId: json['userId'] as String?,
      displayName: json['displayName'] as String?,
      email: json['email'] as String?,
      message: json['message'] as String?,
    );
  }
}

class SyncTransferState {
  const SyncTransferState({
    required this.stage,
    this.message,
    this.remoteStatus,
    this.localBundle,
  });

  const SyncTransferState.idle()
    : stage = SyncTransferStage.idle,
      message = null,
      remoteStatus = null,
      localBundle = null;

  final SyncTransferStage stage;
  final String? message;
  final RemoteSyncBundleStatus? remoteStatus;
  final StoredSyncBundle? localBundle;

  bool get isBusy => stage == SyncTransferStage.busy;

  SyncTransferState copyWith({
    SyncTransferStage? stage,
    String? message,
    RemoteSyncBundleStatus? remoteStatus,
    StoredSyncBundle? localBundle,
    bool clearMessage = false,
  }) {
    return SyncTransferState(
      stage: stage ?? this.stage,
      message: clearMessage ? null : (message ?? this.message),
      remoteStatus: remoteStatus ?? this.remoteStatus,
      localBundle: localBundle ?? this.localBundle,
    );
  }
}

abstract class DeviceAuthGateway {
  Future<DeviceAuthState> checkAvailability();

  Future<bool> authenticate({
    required String reason,
    bool biometricOnly = false,
  });
}

class LocalDeviceAuthGateway implements DeviceAuthGateway {
  LocalDeviceAuthGateway({LocalAuthentication? localAuth})
    : _localAuth = localAuth ?? LocalAuthentication();

  final LocalAuthentication _localAuth;

  @override
  Future<DeviceAuthState> checkAvailability() async {
    if (kIsWeb) {
      return const DeviceAuthState(
        availability: DeviceAuthAvailability.unavailable,
        methods: [],
        lastError: 'Device authentication is not available on web.',
      );
    }

    try {
      final supported = await _localAuth.isDeviceSupported();
      final biometrics = await _localAuth.getAvailableBiometrics();
      final methods = biometrics.map(_labelForBiometric).toSet().toList()
        ..sort();
      return DeviceAuthState(
        availability: supported
            ? DeviceAuthAvailability.available
            : DeviceAuthAvailability.unavailable,
        methods: methods,
      );
    } on MissingPluginException {
      return const DeviceAuthState(
        availability: DeviceAuthAvailability.unavailable,
        methods: [],
        lastError:
            'Device authentication plugin is not configured in this runtime.',
      );
    } on PlatformException catch (error) {
      return DeviceAuthState(
        availability: DeviceAuthAvailability.unavailable,
        methods: const [],
        lastError: error.message ?? error.code,
      );
    } catch (error) {
      return DeviceAuthState(
        availability: DeviceAuthAvailability.unavailable,
        methods: const [],
        lastError: '$error',
      );
    }
  }

  @override
  Future<bool> authenticate({
    required String reason,
    bool biometricOnly = false,
  }) async {
    if (kIsWeb) {
      return false;
    }

    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        options: AuthenticationOptions(
          biometricOnly: biometricOnly,
          stickyAuth: true,
        ),
      );
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  String _labelForBiometric(BiometricType type) {
    switch (type) {
      case BiometricType.face:
        return 'Face ID';
      case BiometricType.fingerprint:
        return 'Fingerprint';
      case BiometricType.iris:
        return 'Iris';
      case BiometricType.strong:
        return 'Strong biometrics';
      case BiometricType.weak:
        return 'Weak biometrics';
    }
  }
}

abstract class SyncAuthGateway {
  Future<SyncAuthState> connect(SyncProvider provider);

  Future<void> disconnect(SyncProvider provider);
}

class DefaultSyncAuthGateway implements SyncAuthGateway {
  static const _googleScopes = <String>[
    'https://www.googleapis.com/auth/drive.appdata',
  ];

  bool _googleInitialized = false;

  @override
  Future<SyncAuthState> connect(SyncProvider provider) {
    return switch (provider) {
      SyncProvider.off => Future.value(SyncAuthState.idle(provider)),
      SyncProvider.googleDrive => _connectGoogle(),
      SyncProvider.iCloud => _connectApple(),
    };
  }

  @override
  Future<void> disconnect(SyncProvider provider) async {
    try {
      if (provider == SyncProvider.googleDrive && !kIsWeb) {
        await _ensureGoogleInitialized();
        await GoogleSignIn.instance.disconnect();
      }
    } catch (_) {}
  }

  Future<void> _ensureGoogleInitialized() async {
    if (_googleInitialized || kIsWeb) {
      return;
    }
    await GoogleSignIn.instance.initialize();
    _googleInitialized = true;
  }

  Future<SyncAuthState> _connectGoogle() async {
    try {
      await _ensureGoogleInitialized();
      GoogleSignInAccount? account;
      final lightweight = GoogleSignIn.instance
          .attemptLightweightAuthentication();
      if (lightweight != null) {
        account = await lightweight;
      }
      if (account == null) {
        if (!GoogleSignIn.instance.supportsAuthenticate()) {
          return const SyncAuthState(
            provider: SyncProvider.googleDrive,
            stage: SyncAuthStage.unsupported,
            message:
                'Google sign-in on this platform needs explicit client ID setup and a user-triggered SDK button.',
          );
        }
        account = await GoogleSignIn.instance.authenticate(
          scopeHint: _googleScopes,
        );
      }

      final existingAuthorization = await account.authorizationClient
          .authorizationForScopes(_googleScopes);
      if (existingAuthorization == null) {
        await account.authorizationClient.authorizeScopes(_googleScopes);
      }

      return SyncAuthState(
        provider: SyncProvider.googleDrive,
        stage: SyncAuthStage.authenticated,
        userId: account.id,
        displayName: account.displayName,
        email: account.email,
        message: 'Google Drive app-data access is authorized.',
      );
    } on MissingPluginException {
      return const SyncAuthState(
        provider: SyncProvider.googleDrive,
        stage: SyncAuthStage.unsupported,
        message: 'Google sign-in plugin is not configured in this runtime.',
      );
    } catch (error) {
      return SyncAuthState(
        provider: SyncProvider.googleDrive,
        stage: SyncAuthStage.error,
        message: '$error',
      );
    }
  }

  Future<SyncAuthState> _connectApple() async {
    final supportsAppleSignIn =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);
    if (!supportsAppleSignIn) {
      return const SyncAuthState(
        provider: SyncProvider.iCloud,
        stage: SyncAuthStage.unsupported,
        message:
            'Apple ID authentication for iCloud sync is only available on iOS and macOS in this build.',
      );
    }

    try {
      if (!await SignInWithApple.isAvailable()) {
        return const SyncAuthState(
          provider: SyncProvider.iCloud,
          stage: SyncAuthStage.unsupported,
          message: 'Apple ID authentication is not available on this device.',
        );
      }

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final fullName = [
        credential.givenName,
        credential.familyName,
      ].whereType<String>().where((part) => part.trim().isNotEmpty).join(' ');

      return SyncAuthState(
        provider: SyncProvider.iCloud,
        stage: SyncAuthStage.authenticated,
        userId: credential.userIdentifier,
        displayName: fullName.isEmpty ? 'Apple ID user' : fullName,
        email: credential.email,
        message:
            'Apple ID credential captured. Server-side validation is still required before real iCloud sync.',
      );
    } on MissingPluginException {
      return const SyncAuthState(
        provider: SyncProvider.iCloud,
        stage: SyncAuthStage.unsupported,
        message: 'Apple sign-in plugin is not configured in this runtime.',
      );
    } catch (error) {
      return SyncAuthState(
        provider: SyncProvider.iCloud,
        stage: SyncAuthStage.error,
        message: '$error',
      );
    }
  }
}

abstract class MediaImportService {
  Future<MediaImportResult> importAttachment(MediaImportAction action);
}

class DefaultMediaImportService implements MediaImportService {
  DefaultMediaImportService({required EncryptedAttachmentStore attachmentStore})
    : _attachmentStore = attachmentStore;

  final EncryptedAttachmentStore _attachmentStore;

  @override
  Future<MediaImportResult> importAttachment(MediaImportAction action) async {
    switch (action) {
      case MediaImportAction.takePhoto:
        return _pickPhoto(ImageSource.camera);
      case MediaImportAction.pickPhoto:
        return _pickPhoto(ImageSource.gallery);
      case MediaImportAction.recordVideo:
        return _pickVideo(ImageSource.camera);
      case MediaImportAction.pickVideo:
        return _pickVideo(ImageSource.gallery);
      case MediaImportAction.pickAudio:
        return _pickAudio();
    }
  }

  Future<MediaImportResult> _pickPhoto(ImageSource source) async {
    XFile? picked;
    try {
      final picker = ImagePicker();
      picked = await picker.pickImage(
        source: source,
        imageQuality: 88,
        maxWidth: 1800,
      );
    } on MissingPluginException {
      return const MediaImportResult.failure(
        'Photo import is not configured in this runtime.',
      );
    } on PlatformException catch (error) {
      return MediaImportResult.failure(
        error.message ?? 'Photo import failed on this device.',
      );
    }
    if (picked == null) {
      return const MediaImportResult.cancelled();
    }
    final tooLarge = await _validateFileSize(
      picked,
      maxBytes: 25 * 1024 * 1024,
      tooLargeMessage: 'Photos over 25 MB are not supported yet.',
    );
    if (tooLarge != null) {
      return tooLarge;
    }
    return MediaImportResult.success(
      await _buildAttachment(
      type: AttachmentType.photo,
      sourceFile: picked,
      ),
    );
  }

  Future<MediaImportResult> _pickVideo(ImageSource source) async {
    XFile? picked;
    try {
      final picker = ImagePicker();
      picked = await picker.pickVideo(source: source);
    } on MissingPluginException {
      return const MediaImportResult.failure(
        'Video import is not configured in this runtime.',
      );
    } on PlatformException catch (error) {
      return MediaImportResult.failure(
        error.message ?? 'Video import failed on this device.',
      );
    }
    if (picked == null) {
      return const MediaImportResult.cancelled();
    }
    final tooLarge = await _validateFileSize(
      picked,
      maxBytes: 200 * 1024 * 1024,
      tooLargeMessage: 'Videos over 200 MB are not supported yet.',
    );
    if (tooLarge != null) {
      return tooLarge;
    }
    return MediaImportResult.success(
      await _buildAttachment(type: AttachmentType.video, sourceFile: picked),
    );
  }

  Future<MediaImportResult> _pickAudio() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        withData: kIsWeb,
      );
    } on MissingPluginException {
      return const MediaImportResult.failure(
        'Audio import is not configured in this runtime.',
      );
    } on PlatformException catch (error) {
      return MediaImportResult.failure(
        error.message ?? 'Audio import failed on this device.',
      );
    }
    if (result == null || result.files.isEmpty) {
      return const MediaImportResult.cancelled();
    }

    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes != null && bytes.length > 50 * 1024 * 1024) {
      return const MediaImportResult.failure(
        'Audio files over 50 MB are not supported yet.',
      );
    }
    final sourceFile = file.path == null
        ? XFile.fromData(file.bytes!, name: file.name)
        : XFile(file.path!, name: file.name);
    final tooLarge = await _validateFileSize(
      sourceFile,
      maxBytes: 50 * 1024 * 1024,
      tooLargeMessage: 'Audio files over 50 MB are not supported yet.',
    );
    if (tooLarge != null) {
      return tooLarge;
    }
    return MediaImportResult.success(
      await _buildAttachment(type: AttachmentType.audio, sourceFile: sourceFile),
    );
  }

  Future<NoteAttachment> _buildAttachment({
    required AttachmentType type,
    required XFile sourceFile,
  }) async {
    final storedPath = await _attachmentStore.storeAttachment(
      sourceFile,
      type: type,
    );
    return NoteAttachment(
      type: type,
      label: sourceFile.name.isEmpty
          ? path.basename(sourceFile.path)
          : sourceFile.name,
      filePath: storedPath,
    );
  }

  Future<MediaImportResult?> _validateFileSize(
    XFile file, {
    required int maxBytes,
    required String tooLargeMessage,
  }) async {
    if (kIsWeb) {
      return null;
    }
    final length = await file.length();
    if (length > maxBytes) {
      return MediaImportResult.failure(tooLargeMessage);
    }
    return null;
  }
}

final deviceAuthGatewayProvider = Provider<DeviceAuthGateway>(
  (ref) => LocalDeviceAuthGateway(),
);

final syncAuthGatewayProvider = Provider<SyncAuthGateway>(
  (ref) => DefaultSyncAuthGateway(),
);

final mediaImportServiceProvider = Provider<MediaImportService>(
  (ref) => DefaultMediaImportService(
    attachmentStore: ref.watch(encryptedAttachmentStoreProvider),
  ),
);

final secureKeyValueStoreProvider = Provider<SecureKeyValueStore>((ref) {
  return FlutterSecureKeyValueStore();
});

final encryptionServiceProvider = Provider<EncryptionService>((ref) {
  return EncryptionService();
});

final masterKeyServiceProvider = Provider<MasterKeyService>((ref) {
  final encryption = ref.watch(encryptionServiceProvider);
  return MasterKeyService(
    secureStore: ref.watch(secureKeyValueStoreProvider),
    keyFactory: encryption.generateKeyBytes,
  );
});

final encryptedNoteStoreProvider = Provider<EncryptedNoteStore>((ref) {
  return EncryptedNoteStore(
    encryptionService: ref.watch(encryptionServiceProvider),
    masterKeyService: ref.watch(masterKeyServiceProvider),
    database: ref.watch(encryptedNoteDatabaseProvider),
  );
});

final encryptedNoteDatabaseProvider = Provider<EncryptedNoteDatabase>((ref) {
  final database = EncryptedNoteDatabase();
  ref.onDispose(database.close);
  return database;
});

final deviceIdentityStoreProvider = Provider<DeviceIdentityStore>((ref) {
  return DeviceIdentityStore();
});

final encryptedAttachmentStoreProvider = Provider<EncryptedAttachmentStore>((
  ref,
) {
  return EncryptedAttachmentStore(
    encryptionService: ref.watch(encryptionServiceProvider),
    masterKeyService: ref.watch(masterKeyServiceProvider),
  );
});

final syncEngineProvider = Provider<SyncEngine>((ref) {
  return SyncEngine(
    database: ref.watch(encryptedNoteDatabaseProvider),
    attachmentStore: ref.watch(encryptedAttachmentStoreProvider),
    deviceIdentityStore: ref.watch(deviceIdentityStoreProvider),
  );
});

final secureSyncBundleStoreProvider = Provider<SecureSyncBundleStore>((ref) {
  return SecureSyncBundleStore(
    encryptionService: ref.watch(encryptionServiceProvider),
    syncBundleKeyService: ref.watch(syncBundleKeyServiceProvider),
    legacyMasterKeyService: ref.watch(masterKeyServiceProvider),
  );
});

final syncBundleKeyServiceProvider = Provider<SyncBundleKeyService>((ref) {
  final encryption = ref.watch(encryptionServiceProvider);
  return SyncBundleKeyService(
    secureStore: ref.watch(secureKeyValueStoreProvider),
    keyFactory: encryption.generateKeyBytes,
  );
});

final syncBundleFingerprintProvider = FutureProvider<String>((ref) async {
  return ref.watch(syncBundleKeyServiceProvider).fingerprint();
});

final googleDriveSyncTransportProvider = Provider<GoogleDriveSyncTransport>((
  ref,
) {
  return GoogleApisGoogleDriveSyncTransport();
});

final syncBundleStateStoreProvider = Provider<SyncBundleStateStore>((ref) {
  return SyncBundleStateStore();
});

final syncBundleStateProvider = FutureProvider<SyncBundleState>((ref) async {
  return ref.watch(syncBundleStateStoreProvider).read();
});

final syncConflictWarningProvider = Provider<String?>((ref) {
  final assessment = assessSyncConflict(
    googleDriveSelected:
        ref.watch(syncProviderControllerProvider) == SyncProvider.googleDrive,
    queue: ref.watch(syncQueueSummaryProvider).asData?.value,
    remoteStatus: ref.watch(syncTransferControllerProvider).remoteStatus,
    bundleState: ref.watch(syncBundleStateProvider).asData?.value,
  );
  return assessment.message;
});

final syncQueueSummaryProvider = FutureProvider<SyncQueueSummary>((ref) async {
  ref.watch(notesControllerProvider);
  return ref.watch(syncEngineProvider).summarizeQueue();
});

final syncTransferControllerProvider =
    NotifierProvider<SyncTransferController, SyncTransferState>(
      SyncTransferController.new,
    );

class SyncTransferController extends Notifier<SyncTransferState> {
  @override
  SyncTransferState build() => const SyncTransferState.idle();

  Future<void> refreshRemoteStatus() async {
    if (ref.read(syncProviderControllerProvider) != SyncProvider.googleDrive) {
      state = const SyncTransferState(
        stage: SyncTransferStage.idle,
        message: 'Remote status is only available for Google Drive right now.',
      );
      return;
    }
    state = state.copyWith(stage: SyncTransferStage.busy, clearMessage: true);
    try {
      final remoteStatus = await ref
          .read(googleDriveSyncTransportProvider)
          .fetchLatestBundleStatus();
      state = SyncTransferState(
        stage: SyncTransferStage.success,
        message: remoteStatus == null
            ? 'No Google Drive bundle is stored yet.'
            : 'Google Drive bundle metadata refreshed.',
        remoteStatus: remoteStatus,
        localBundle: state.localBundle,
      );
      if (remoteStatus != null) {
        await ref.read(syncBundleStateStoreProvider).recordRemoteStatus(
          remoteStatus,
        );
      }
    } catch (error) {
      state = SyncTransferState(
        stage: SyncTransferStage.error,
        message: '$error',
        remoteStatus: state.remoteStatus,
      );
    }
  }

  Future<void> uploadCurrentBundle({bool force = false}) async {
    if (ref.read(syncProviderControllerProvider) != SyncProvider.googleDrive) {
      state = const SyncTransferState(
        stage: SyncTransferStage.error,
        message: 'Switch the sync target to Google Drive before uploading.',
      );
      return;
    }
    final assessment = assessSyncConflict(
      googleDriveSelected: true,
      queue: await ref.read(syncQueueSummaryProvider.future),
      remoteStatus: state.remoteStatus,
      bundleState: await ref.read(syncBundleStateProvider.future),
    );
    if (assessment.hasConflict && !force) {
      state = state.copyWith(
        stage: SyncTransferStage.error,
        message:
            '${assessment.message} Download and apply the remote bundle first, or use Force upload if you intend to overwrite it.',
      );
      return;
    }
    state = state.copyWith(stage: SyncTransferStage.busy, clearMessage: true);
    try {
      final snapshot = await ref
          .read(syncEngineProvider)
          .prepareSnapshot(ref.read(notesControllerProvider));
      final bundle = await ref
          .read(secureSyncBundleStoreProvider)
          .writeBundle(snapshot);
      final encodedPayload = await ref
          .read(secureSyncBundleStoreProvider)
          .readEncryptedBundlePayload(bundle.reference);
      if (encodedPayload == null || encodedPayload.isEmpty) {
        throw StateError('Local sync bundle could not be prepared.');
      }
      final remoteStatus = await ref
          .read(googleDriveSyncTransportProvider)
          .uploadBundle(
            encodedPayload: encodedPayload,
            deviceId: snapshot.deviceId,
            noteCount: bundle.noteCount,
            attachmentCount: bundle.attachmentCount,
          );
      await ref.read(notesControllerProvider.notifier).markCurrentStateSynced();
      state = SyncTransferState(
        stage: SyncTransferStage.success,
        message: 'Encrypted bundle uploaded to Google Drive app-data.',
        remoteStatus: remoteStatus,
        localBundle: bundle,
      );
      await ref.read(syncBundleStateStoreProvider).recordUpload(remoteStatus);
    } catch (error) {
      state = SyncTransferState(
        stage: SyncTransferStage.error,
        message: '$error',
        remoteStatus: state.remoteStatus,
        localBundle: state.localBundle,
      );
    }
  }

  Future<void> downloadLatestBundle() async {
    if (ref.read(syncProviderControllerProvider) != SyncProvider.googleDrive) {
      state = const SyncTransferState(
        stage: SyncTransferStage.error,
        message: 'Switch the sync target to Google Drive before downloading.',
      );
      return;
    }
    state = state.copyWith(stage: SyncTransferStage.busy, clearMessage: true);
    try {
      final remoteBundle = await ref
          .read(googleDriveSyncTransportProvider)
          .downloadLatestBundle();
      if (remoteBundle == null) {
        state = const SyncTransferState(
          stage: SyncTransferStage.success,
          message: 'No remote Google Drive bundle is available.',
        );
        return;
      }
      final localBundle = await ref
          .read(secureSyncBundleStoreProvider)
          .writeEncryptedBundlePayload(
            remoteBundle.encodedPayload,
            noteCount: remoteBundle.status.noteCount ?? 0,
            attachmentCount: remoteBundle.status.attachmentCount ?? 0,
            fileNameOverride: 'downloaded_sync_bundle.enc',
          );
      state = SyncTransferState(
        stage: SyncTransferStage.success,
        message: 'Remote Google Drive bundle downloaded to local secure storage.',
        remoteStatus: remoteBundle.status,
        localBundle: localBundle,
      );
      await ref.read(syncBundleStateStoreProvider).recordRemoteStatus(
        remoteBundle.status,
      );
    } catch (error) {
      state = SyncTransferState(
        stage: SyncTransferStage.error,
        message: '$error',
        remoteStatus: state.remoteStatus,
        localBundle: state.localBundle,
      );
    }
  }

  Future<void> applyDownloadedBundle() async {
    final localBundle = state.localBundle;
    if (localBundle == null) {
      state = state.copyWith(
        stage: SyncTransferStage.error,
        message: 'Download a remote bundle before applying it.',
      );
      return;
    }
    state = state.copyWith(stage: SyncTransferStage.busy, clearMessage: true);
    try {
      final decoded = await ref
          .read(secureSyncBundleStoreProvider)
          .readBundleJson(localBundle.reference);
      if (decoded == null) {
        throw StateError('Downloaded bundle could not be decrypted.');
      }
      final attachmentPayloads = <String, Map<String, dynamic>>{
        for (final entry
            in (decoded['attachments'] as List<dynamic>? ?? const <dynamic>[]))
          (entry as Map)['id'] as String: Map<String, dynamic>.from(entry),
      };
      final importedNotes = <NoteEntry>[];
      for (final rawEntry
          in (decoded['notes'] as List<dynamic>? ?? const <dynamic>[])) {
        final entry = Map<String, dynamic>.from(rawEntry as Map);
        final note = NoteEntry.fromJson(
          Map<String, dynamic>.from(entry['note'] as Map),
        );
        final importedAttachments = <NoteAttachment>[];
        for (final attachment in note.attachments) {
          final filePath = attachment.filePath;
          if (filePath == null || !filePath.startsWith('sync-attachment://')) {
            importedAttachments.add(attachment);
            continue;
          }
          final attachmentId = filePath.substring('sync-attachment://'.length);
          final payload = attachmentPayloads[attachmentId];
          if (payload == null) {
            importedAttachments.add(attachment.copyWith(filePath: null));
            continue;
          }
          final storedReference = await ref
              .read(encryptedAttachmentStoreProvider)
              .storeEncryptedPayload(
                encodedPayload: payload['encryptedPayload'] as String,
                type: AttachmentType.values.firstWhere(
                  (value) => value.name == payload['type'],
                  orElse: () => attachment.type,
                ),
                fileNameHint: payload['label'] as String? ?? attachment.label,
              );
          importedAttachments.add(attachment.copyWith(filePath: storedReference));
        }
        importedNotes.add(note.copyWith(attachments: importedAttachments));
      }
      await ref.read(notesControllerProvider.notifier).replaceFromSync(
        importedNotes,
      );
      await ref.read(syncBundleStateStoreProvider).recordApply(state.remoteStatus);
      state = state.copyWith(
        stage: SyncTransferStage.success,
        message: 'Downloaded bundle applied to local notes.',
      );
    } catch (error) {
      state = state.copyWith(
        stage: SyncTransferStage.error,
        message: '$error',
      );
    }
  }
}

final privateVaultSecretStoreProvider = Provider<PrivateVaultSecretStore>((ref) {
  return PrivateVaultSecretStore(
    secureStore: ref.watch(secureKeyValueStoreProvider),
    encryptionService: ref.watch(encryptionServiceProvider),
  );
});

@Riverpod(keepAlive: true)
HomeRepository homeRepository(Ref ref) => SeededHomeRepository();

final appSessionUnlockControllerProvider =
    NotifierProvider<AppSessionUnlockController, bool>(
      AppSessionUnlockController.new,
    );

class AppSessionUnlockController extends Notifier<bool> {
  @override
  bool build() => false;

  void unlock() => state = true;

  void lock() => state = false;
}

final deviceAuthControllerProvider =
    NotifierProvider<DeviceAuthController, DeviceAuthState>(
      DeviceAuthController.new,
    );

class DeviceAuthController extends Notifier<DeviceAuthState> {
  @override
  DeviceAuthState build() {
    unawaited(refresh());
    return const DeviceAuthState.unknown();
  }

  Future<void> refresh() async {
    state = await ref.read(deviceAuthGatewayProvider).checkAvailability();
  }

  Future<bool> authenticate({
    required String reason,
    bool biometricOnly = false,
  }) async {
    final authenticated = await ref
        .read(deviceAuthGatewayProvider)
        .authenticate(reason: reason, biometricOnly: biometricOnly);
    await refresh();
    if (authenticated) {
      ref.read(appSessionUnlockControllerProvider.notifier).unlock();
    }
    return authenticated;
  }
}

final syncAuthControllerProvider =
    NotifierProvider<SyncAuthController, Map<SyncProvider, SyncAuthState>>(
      SyncAuthController.new,
    );

class SyncAuthController extends Notifier<Map<SyncProvider, SyncAuthState>> {
  static const _storageKey = 'sync.auth_accounts.v1';
  bool _restored = false;

  @override
  Map<SyncProvider, SyncAuthState> build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return {
      for (final provider in SyncProvider.values)
        provider: SyncAuthState.idle(provider),
    };
  }

  SyncAuthState stateFor(SyncProvider provider) =>
      state[provider] ?? SyncAuthState.idle(provider);

  Future<void> connectSelected() async {
    await connect(ref.read(syncProviderControllerProvider));
  }

  Future<void> connect(SyncProvider provider) async {
    if (provider == SyncProvider.off) {
      _update(provider, SyncAuthState.idle(provider));
      return;
    }

    _update(
      provider,
      stateFor(
        provider,
      ).copyWith(stage: SyncAuthStage.busy, clearMessage: true),
    );

    final next = await ref.read(syncAuthGatewayProvider).connect(provider);

    _update(provider, next);
    await _persist();
  }

  Future<void> disconnectSelected() async {
    await disconnect(ref.read(syncProviderControllerProvider));
  }

  Future<void> disconnect(SyncProvider provider) async {
    await ref.read(syncAuthGatewayProvider).disconnect(provider);
    _update(provider, SyncAuthState.idle(provider));
    await _persist();
  }

  void _update(SyncProvider provider, SyncAuthState next) {
    state = {...state, provider: next};
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_storageKey);
      if (stored == null || stored.isEmpty) {
        return;
      }
      final decoded = Map<String, dynamic>.from(
        jsonDecode(stored) as Map<String, dynamic>,
      );
      state = {
        for (final provider in SyncProvider.values)
          provider: decoded[provider.name] == null
              ? SyncAuthState.idle(provider)
              : SyncAuthState.fromJson(
                  Map<String, dynamic>.from(decoded[provider.name] as Map),
                ),
      };
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode({
        for (final entry in state.entries) entry.key.name: entry.value.toJson(),
      });
      await prefs.setString(_storageKey, encoded);
    } catch (_) {}
  }
}

final appLaunchControllerProvider =
    NotifierProvider<AppLaunchController, AppLaunchSurface>(
      AppLaunchController.new,
    );

class AppLaunchController extends Notifier<AppLaunchSurface> {
  static const _storageKey = 'app.onboarding_completed';
  bool _restored = false;

  @override
  AppLaunchSurface build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return AppLaunchSurface.onboarding;
  }

  Future<void> completeOnboarding() async {
    state = AppLaunchSurface.ready;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_storageKey, true);
    } catch (_) {}
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final completed = prefs.getBool(_storageKey) ?? false;
      state = completed ? AppLaunchSurface.ready : AppLaunchSurface.onboarding;
    } catch (_) {
      state = AppLaunchSurface.onboarding;
    }
  }
}

@Riverpod(keepAlive: true)
class ThemeModeController extends _$ThemeModeController {
  static const _storageKey = 'settings.theme_mode';
  bool _restored = false;

  @override
  ThemeMode build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return ThemeMode.light;
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, mode.name);
    } catch (_) {}
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_storageKey);
      if (stored == null) {
        return;
      }

      state = ThemeMode.values.firstWhere(
        (mode) => mode.name == stored,
        orElse: () => ThemeMode.light,
      );
    } catch (_) {}
  }
}

final appColorThemeControllerProvider =
    NotifierProvider<AppColorThemeController, AppColorTheme>(
      AppColorThemeController.new,
    );

class AppColorThemeController extends Notifier<AppColorTheme> {
  static const _storageKey = 'settings.color_theme';
  bool _restored = false;

  @override
  AppColorTheme build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return AppColorTheme.blue;
  }

  Future<void> setTheme(AppColorTheme theme) async {
    state = theme;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, theme.name);
    } catch (_) {}
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_storageKey);
      if (stored == null) {
        return;
      }

      state = AppColorTheme.values.firstWhere(
        (theme) => theme.name == stored,
        orElse: () => AppColorTheme.blue,
      );
    } catch (_) {}
  }
}

final appLockSettingsControllerProvider =
    NotifierProvider<AppLockSettingsController, bool>(
      AppLockSettingsController.new,
    );

class AppLockSettingsController extends Notifier<bool> {
  static const _storageKey = 'settings.app_lock_enabled';
  bool _restored = false;

  @override
  bool build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return false;
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_storageKey, enabled);
    } catch (_) {}
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getBool(_storageKey) ?? false;
    } catch (_) {}
  }
}

final appLockRelockDelayControllerProvider =
    NotifierProvider<AppLockRelockDelayController, AppLockRelockDelay>(
      AppLockRelockDelayController.new,
    );

class AppLockRelockDelayController extends Notifier<AppLockRelockDelay> {
  static const _storageKey = 'settings.app_lock_relock_delay';
  bool _restored = false;

  @override
  AppLockRelockDelay build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return AppLockRelockDelay.immediate;
  }

  Future<void> setDelay(AppLockRelockDelay delay) async {
    state = delay;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, delay.name);
    } catch (_) {}
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_storageKey);
      if (stored == null) {
        return;
      }
      state = AppLockRelockDelay.values.firstWhere(
        (delay) => delay.name == stored,
        orElse: () => AppLockRelockDelay.immediate,
      );
    } catch (_) {}
  }
}

final privateVaultLockOnAppLockControllerProvider =
    NotifierProvider<PrivateVaultLockOnAppLockController, bool>(
      PrivateVaultLockOnAppLockController.new,
    );

class PrivateVaultLockOnAppLockController extends Notifier<bool> {
  static const _storageKey = 'settings.private_vault_lock_on_app_lock';
  bool _restored = false;

  @override
  bool build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return true;
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_storageKey, enabled);
    } catch (_) {}
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getBool(_storageKey) ?? true;
    } catch (_) {}
  }
}

final syncProviderControllerProvider =
    NotifierProvider<SyncProviderController, SyncProvider>(
      SyncProviderController.new,
    );

class SyncProviderController extends Notifier<SyncProvider> {
  static const _storageKey = 'settings.sync_provider';
  bool _restored = false;

  @override
  SyncProvider build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return SyncProvider.off;
  }

  Future<void> setProvider(SyncProvider provider) async {
    state = provider;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, provider.name);
    } catch (_) {}
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_storageKey);
      if (stored == null) {
        return;
      }
      state = SyncProvider.values.firstWhere(
        (provider) => provider.name == stored,
        orElse: () => SyncProvider.off,
      );
    } catch (_) {}
  }
}

final privateVaultSessionControllerProvider =
    NotifierProvider<PrivateVaultSessionController, bool>(
      PrivateVaultSessionController.new,
    );

class PrivateVaultSessionController extends Notifier<bool> {
  @override
  bool build() => false;

  void unlock() => state = true;

  void lock() => state = false;
}

final privateVaultSecretControllerProvider =
    NotifierProvider<PrivateVaultSecretController, bool>(
      PrivateVaultSecretController.new,
    );

class PrivateVaultSecretController extends Notifier<bool> {
  bool _restored = false;

  @override
  bool build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return false;
  }

  Future<void> configure(String secret) async {
    await ref.read(privateVaultSecretStoreProvider).configure(secret);
    state = true;
    ref.read(privateVaultSessionControllerProvider.notifier).unlock();
  }

  Future<bool> verify(String secret) async {
    try {
      final matched = await ref.read(privateVaultSecretStoreProvider).verify(
        secret,
      );
      if (matched) {
        ref.read(privateVaultSessionControllerProvider.notifier).unlock();
      }
      return matched;
    } catch (_) {
      return false;
    }
  }

  Future<void> clear() async {
    try {
      await ref.read(privateVaultSecretStoreProvider).clear();
    } catch (_) {}
    state = false;
    ref.read(privateVaultSessionControllerProvider.notifier).lock();
  }

  Future<void> _restore() async {
    try {
      state = await ref.read(privateVaultSecretStoreProvider).hasSecret();
    } catch (_) {}
  }
}

@Riverpod(keepAlive: true)
class ActiveIdentity extends _$ActiveIdentity {
  static const _storageKey = 'settings.active_identity';
  bool _restored = false;

  @override
  String build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return 'daily';
  }

  Future<void> switchTo(String identityId) async {
    state = identityId;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, identityId);
    } catch (_) {}
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_storageKey);
      if (stored != null) {
        state = stored;
      }
    } catch (_) {}
  }
}

@Riverpod(keepAlive: true)
class SearchQuery extends _$SearchQuery {
  @override
  String build() => '';

  void setQuery(String value) => state = value;
}

@Riverpod(keepAlive: true)
class NotesController extends _$NotesController {
  bool _restored = false;

  @override
  List<NoteEntry> build() {
    final seeded = ref.read(homeRepositoryProvider).seededNotes;
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return List<NoteEntry>.from(seeded);
  }

  Future<void> upsert(NoteEntry note) async {
    final next = [...state];
    final index = next.indexWhere((entry) => entry.id == note.id);
    final existing = index == -1 ? null : next[index];
    final prepared = await _prepareForSave(note, previous: existing);
    if (index == -1) {
      next.add(prepared);
    } else {
      next[index] = prepared;
    }
    _sort(next);
    state = next;
    await _cleanupRemovedAttachments(existing, prepared);
    await _persist();
  }

  Future<void> delete(String noteId) async {
    final next = [...state];
    for (var i = 0; i < next.length; i++) {
      final note = next[i];
      if (note.id != noteId) {
        continue;
      }
      final now = DateTime.now();
      final tombstone = note.copyWith(
        deletedAt: now,
        updatedAt: now,
        revision: note.revision + 1,
        syncState: NoteSyncState.pendingDelete,
      );
      next[i] = tombstone.copyWith(contentHash: _computeContentHash(tombstone));
      break;
    }
    _sort(next);
    state = next;
    await _persist();
  }

  Future<void> seedIfEmpty() async {
    if (state.isNotEmpty) {
      return;
    }
    state = List<NoteEntry>.from(ref.read(homeRepositoryProvider).seededNotes);
    _sort(state);
    await _persist();
  }

  Future<void> replaceFromSync(List<NoteEntry> notes) async {
    final incomingPaths = notes
        .expand((note) => note.attachments)
        .map((attachment) => attachment.filePath)
        .whereType<String>()
        .toSet();
    final removedAttachments = [
      for (final existing in state)
        for (final attachment in existing.attachments)
          if (attachment.filePath != null &&
              !incomingPaths.contains(attachment.filePath))
            attachment,
    ];
    await _deleteAttachments(removedAttachments);
    final next = [...notes];
    _sort(next);
    state = next;
    await _persist();
  }

  Future<void> markCurrentStateSynced() async {
    var changed = false;
    final next = <NoteEntry>[];
    for (final note in state) {
      if (note.syncState == NoteSyncState.pendingUpload ||
          note.syncState == NoteSyncState.pendingDelete) {
        next.add(note.copyWith(syncState: NoteSyncState.synced));
        changed = true;
      } else {
        next.add(note);
      }
    }
    if (!changed) {
      return;
    }
    _sort(next);
    state = next;
    await _persist();
  }

  Future<void> _restore() async {
    try {
      final restored = [
        ...await ref
            .read(encryptedNoteStoreProvider)
            .load(fallbackNotes: ref.read(homeRepositoryProvider).seededNotes),
      ];
      _sort(restored);
      state = restored;
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      await ref.read(encryptedNoteStoreProvider).save(state);
    } catch (_) {}
  }

  Future<void> _cleanupRemovedAttachments(
    NoteEntry? previous,
    NoteEntry next,
  ) async {
    if (previous == null) {
      return;
    }
    final retained = next.attachments
        .map((attachment) => attachment.filePath)
        .whereType<String>()
        .toSet();
    final removed = previous.attachments
        .where((attachment) {
          final filePath = attachment.filePath;
          return filePath != null && !retained.contains(filePath);
        })
        .toList(growable: false);
    await _deleteAttachments(removed);
  }

  Future<void> _deleteAttachments(List<NoteAttachment> attachments) async {
    final attachmentStore = ref.read(encryptedAttachmentStoreProvider);
    for (final attachment in attachments) {
      final filePath = attachment.filePath;
      if (filePath == null || filePath.isEmpty) {
        continue;
      }
      await attachmentStore.deleteAttachment(filePath);
    }
  }

  Future<NoteEntry> _prepareForSave(
    NoteEntry note, {
    NoteEntry? previous,
  }) async {
    final deviceId =
        note.deviceId ??
        previous?.deviceId ??
        await ref.read(deviceIdentityStoreProvider).obtain();
    final createdAt = previous?.createdAt ?? note.createdAt;
    final updatedAt = note.updatedAt ?? DateTime.now();
    final normalized = note.copyWith(
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: null,
      deviceId: deviceId,
      syncState: NoteSyncState.pendingUpload,
    );
    return normalized.copyWith(contentHash: _computeContentHash(normalized));
  }

  String _computeContentHash(NoteEntry note) {
    final payload = jsonEncode({
      'id': note.id,
      'vaultId': note.vaultId,
      'title': note.title,
      'body': note.body,
      'createdAt': note.createdAt.toIso8601String(),
      'updatedAt': note.updatedAt?.toIso8601String(),
      'deletedAt': note.deletedAt?.toIso8601String(),
      'isPinned': note.isPinned,
      'revision': note.revision,
      'syncState': note.syncState.name,
      'attachments': [
        for (final attachment in note.attachments)
          {
            'type': attachment.type.name,
            'label': attachment.label,
            'filePath': attachment.filePath,
          },
      ],
    });
    return sha256.convert(utf8.encode(payload)).toString();
  }

  void _sort(List<NoteEntry> notes) {
    notes.sort((left, right) {
      if (left.isPinned != right.isPinned) {
        return right.isPinned ? 1 : -1;
      }
      return (right.updatedAt ?? right.createdAt).compareTo(
        left.updatedAt ?? left.createdAt,
      );
    });
  }
}

@riverpod
List<VaultBucket> vaults(Ref ref) => ref.watch(homeRepositoryProvider).vaults;

@riverpod
List<UnlockIdentity> identities(Ref ref) =>
    ref.watch(homeRepositoryProvider).identities;

@riverpod
UnlockIdentity activeIdentityData(Ref ref) {
  final activeId = ref.watch(activeIdentityProvider);
  return ref
      .watch(identitiesProvider)
      .firstWhere((identity) => identity.id == activeId);
}

@riverpod
List<VaultBucket> visibleVaults(Ref ref) {
  final activeIdentity = ref.watch(activeIdentityDataProvider);
  final privateVaultUnlocked = ref.watch(privateVaultSessionControllerProvider);
  return ref
      .watch(vaultsProvider)
      .where((vault) => activeIdentity.visibleVaultIds.contains(vault.id))
      .where((vault) => vault.id != 'private' || privateVaultUnlocked)
      .toList(growable: false);
}

@riverpod
List<NoteEntry> visibleNotes(Ref ref) {
  final visibleIds = ref
      .watch(visibleVaultsProvider)
      .map((vault) => vault.id)
      .toSet();
  final query = ref.watch(searchQueryProvider).trim().toLowerCase();
  final notes = ref
      .watch(notesControllerProvider)
      .where((note) => visibleIds.contains(note.vaultId))
      .where((note) => note.deletedAt == null)
      .where((note) {
        if (query.isEmpty) {
          return true;
        }
        final haystacks = [
          note.title,
          note.body,
          ...note.attachments.map((attachment) => attachment.label),
        ];
        return haystacks.any((value) => value.toLowerCase().contains(query));
      })
      .toList(growable: false);
  return notes;
}

@riverpod
List<NoteEntry> notesForVault(Ref ref, String vaultId) {
  return ref
      .watch(visibleNotesProvider)
      .where((note) => note.vaultId == vaultId)
      .toList(growable: false);
}

@riverpod
SyncAuthState selectedSyncAuthState(Ref ref) {
  final provider = ref.watch(syncProviderControllerProvider);
  final states = ref.watch(syncAuthControllerProvider);
  return states[provider] ?? SyncAuthState.idle(provider);
}

@riverpod
VaultBucket vaultById(Ref ref, String vaultId) {
  return ref.watch(vaultsProvider).firstWhere((vault) => vault.id == vaultId);
}

@riverpod
NoteEntry? noteById(Ref ref, String noteId) {
  for (final note in ref.watch(visibleNotesProvider)) {
    if (note.id == noteId) {
      return note;
    }
  }
  return null;
}
